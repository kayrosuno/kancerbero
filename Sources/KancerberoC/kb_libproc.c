#include "KancerberoC.h"

#include <arpa/inet.h>
#include <errno.h>
#include <libproc.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/socket.h>

int kb_process_list(kb_process **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    int needed = proc_listallpids(NULL, 0);
    if (needed <= 0) {
        return -1;
    }
    size_t capacity = (size_t)needed / sizeof(pid_t) + 32;
    pid_t *pids = NULL;
    int written = 0;

    for (int attempt = 0; attempt < 5; attempt++) {
        pid_t *grown = (pid_t *)realloc(pids, capacity * sizeof(pid_t));
        if (!grown) {
            free(pids);
            return -1;
        }
        pids = grown;
        written = proc_listallpids(pids, (int)(capacity * sizeof(pid_t)));
        if (written < 0) {
            free(pids);
            return -1;
        }
        size_t found = (size_t)written / sizeof(pid_t);
        if (found < capacity) {
            break;
        }
        capacity *= 2;
    }
    if (written <= 0) {
        free(pids);
        return -1;
    }

    size_t found = (size_t)written / sizeof(pid_t);
    kb_process *items = (kb_process *)calloc(found ? found : 1, sizeof(kb_process));
    if (!items) {
        free(pids);
        return -1;
    }

    size_t cursor = 0;
    for (size_t i = 0; i < found; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) {
            continue;
        }
        struct proc_taskallinfo all;
        struct proc_bsdinfo bsd;
        memset(&all, 0, sizeof(all));
        memset(&bsd, 0, sizeof(bsd));

        /*
         * PROC_PIDTASKALLINFO combines the BSD identity and the task CPU/memory
         * counters in one syscall. For another uid without root the kernel
         * returns success with a zeroed structure, so require a real thread
         * count before trusting it. Fall back to PROC_PIDTBSDINFO, which is
         * readable for every process and still provides state and nice.
         */
        int has_task_info = 0;
        int rc = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &all, (int)sizeof(all));
        if (rc == (int)sizeof(all) &&
            (all.ptinfo.pti_threadnum > 0 ||
             all.ptinfo.pti_total_user > 0 ||
             all.ptinfo.pti_total_system > 0)) {
            bsd = all.pbsd;
            has_task_info = 1;
        } else {
            rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, (int)sizeof(bsd));
            if (rc <= 0) {
                continue;
            }
        }

        kb_process *item = &items[cursor++];
        item->pid = (int32_t)pid;
        item->ppid = (int32_t)bsd.pbi_ppid;
        item->uid = (uint32_t)bsd.pbi_uid;
        item->start_time_us = ((uint64_t)bsd.pbi_start_tvsec * 1000000ULL) +
                              (uint64_t)bsd.pbi_start_tvusec;
        item->nice = (int32_t)bsd.pbi_nice;
        item->status = (uint32_t)bsd.pbi_status;
        const char *name = bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm;
        strncpy(item->name, name, sizeof(item->name) - 1);
        proc_pidpath(pid, item->path, (uint32_t)sizeof(item->path));

        if (has_task_info) {
            item->cpu_user_ticks = all.ptinfo.pti_total_user;
            item->cpu_system_ticks = all.ptinfo.pti_total_system;
            item->resident_bytes = all.ptinfo.pti_resident_size;
            item->virtual_bytes = all.ptinfo.pti_virtual_size;
            item->threads = (uint32_t)all.ptinfo.pti_threadnum;
            item->running_threads = (uint32_t)all.ptinfo.pti_numrunning;
            item->priority = (int32_t)all.ptinfo.pti_priority;
            item->has_task_info = 1;
        }
    }

    free(pids);
    *out = items;
    *count = cursor;
    return 0;
}

void kb_process_list_free(kb_process *items)
{
    free(items);
}

int kb_process_path(int32_t pid, char *buffer, size_t size)
{
    if (!buffer || size == 0) {
        return -1;
    }
    int rc = proc_pidpath(pid, buffer, (uint32_t)size);
    if (rc <= 0) {
        buffer[0] = '\0';
        return -1;
    }
    return rc;
}

static struct proc_fdinfo *kb_open_fd_list(int32_t pid, size_t *count)
{
    *count = 0;
    int needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (needed <= 0) {
        return NULL;
    }
    struct proc_fdinfo *fds = (struct proc_fdinfo *)malloc((size_t)needed);
    if (!fds) {
        return NULL;
    }
    int got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, needed);
    if (got <= 0) {
        free(fds);
        return NULL;
    }
    *count = (size_t)got / sizeof(struct proc_fdinfo);
    return fds;
}

static void kb_fill_endpoint(const struct in_sockinfo *info, uint8_t family,
                             uint8_t *local, uint8_t *remote,
                             uint16_t *local_port, uint16_t *remote_port)
{
    int isIPv4 = (info->insi_vflag & INI_IPV4) != 0;
    if (isIPv4) {
        memcpy(local, &info->insi_laddr.ina_46.i46a_addr4, 4);
        memcpy(remote, &info->insi_faddr.ina_46.i46a_addr4, 4);
    } else {
        memcpy(local, &info->insi_laddr.ina_6, 16);
        memcpy(remote, &info->insi_faddr.ina_6, 16);
    }
    (void)family;
    *local_port = ntohs((uint16_t)info->insi_lport);
    *remote_port = ntohs((uint16_t)info->insi_fport);
}

int kb_socket_list(int32_t pid, kb_socket **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    size_t fd_count = 0;
    struct proc_fdinfo *fds = kb_open_fd_list(pid, &fd_count);
    if (!fds) {
        return -1;
    }

    kb_socket *items = (kb_socket *)calloc(fd_count ? fd_count : 1, sizeof(kb_socket));
    if (!items) {
        free(fds);
        return -1;
    }

    size_t cursor = 0;
    for (size_t i = 0; i < fd_count; i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) {
            continue;
        }
        struct socket_fdinfo info;
        memset(&info, 0, sizeof(info));
        int rc = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO,
                                &info, (int)sizeof(info));
        if (rc != (int)sizeof(info)) {
            continue;
        }
        kb_socket *item = &items[cursor++];
        item->pid = pid;
        item->fd = fds[i].proc_fd;
        item->family = info.psi.soi_family;
        item->protocol = info.psi.soi_protocol;
        item->type = info.psi.soi_type;
        item->state = -1;

        const struct in_sockinfo *in = NULL;
        if (info.psi.soi_kind == SOCKINFO_TCP) {
            in = &info.psi.soi_proto.pri_tcp.tcpsi_ini;
            item->state = info.psi.soi_proto.pri_tcp.tcpsi_state;
        } else if (info.psi.soi_kind == SOCKINFO_IN) {
            in = &info.psi.soi_proto.pri_in;
        }
        if (in) {
            item->family = (in->insi_vflag & INI_IPV6) ? 6 : 4;
            kb_fill_endpoint(in, (uint8_t)item->family, item->local_addr,
                             item->remote_addr, &item->local_port, &item->remote_port);
        }
    }

    free(fds);
    *out = items;
    *count = cursor;
    return 0;
}

void kb_socket_list_free(kb_socket *items)
{
    free(items);
}

#define KB_SOCKET_MAX_UNIQUE 16384

typedef struct {
    uint64_t *slots;
    size_t capacity;
    size_t count;
} kb_token_set;

static uint64_t kb_token_hash(uint64_t value)
{
    value ^= value >> 33;
    value *= 0xff51afd7ed558ccdULL;
    value ^= value >> 33;
    value *= 0xc4ceb9fe1a85ec53ULL;
    value ^= value >> 33;
    return value;
}

static int kb_token_set_init(kb_token_set *set, size_t hint)
{
    size_t capacity = 64;
    while (capacity < hint * 2) {
        capacity <<= 1;
    }
    set->slots = (uint64_t *)calloc(capacity, sizeof(uint64_t));
    if (!set->slots) {
        set->capacity = 0;
        set->count = 0;
        return -1;
    }
    set->capacity = capacity;
    set->count = 0;
    return 0;
}

static void kb_token_set_free(kb_token_set *set)
{
    free(set->slots);
    set->slots = NULL;
    set->capacity = 0;
    set->count = 0;
}

static int kb_token_set_grow(kb_token_set *set)
{
    size_t new_capacity = set->capacity * 2;
    uint64_t *slots = (uint64_t *)calloc(new_capacity, sizeof(uint64_t));
    if (!slots) {
        return -1;
    }
    size_t mask = new_capacity - 1;
    for (size_t i = 0; i < set->capacity; i++) {
        uint64_t token = set->slots[i];
        if (token == 0) {
            continue;
        }
        size_t index = (size_t)kb_token_hash(token) & mask;
        while (slots[index] != 0) {
            index = (index + 1) & mask;
        }
        slots[index] = token;
    }
    free(set->slots);
    set->slots = slots;
    set->capacity = new_capacity;
    return 0;
}

/* Returns 1 when the token is new, 0 when already present, -1 on failure. */
static int kb_token_set_insert(kb_token_set *set, uint64_t token)
{
    if (token == 0) {
        return 1;
    }
    if ((set->count + 1) * 10 >= set->capacity * 7) {
        if (kb_token_set_grow(set) != 0) {
            return -1;
        }
    }
    size_t mask = set->capacity - 1;
    size_t index = (size_t)kb_token_hash(token) & mask;
    while (set->slots[index] != 0) {
        if (set->slots[index] == token) {
            return 0;
        }
        index = (index + 1) & mask;
    }
    set->slots[index] = token;
    set->count++;
    return 1;
}

static struct proc_fdinfo *kb_open_fd_list_status(int32_t pid, size_t *count,
                                                  int *restricted)
{
    *count = 0;
    *restricted = 0;
    int needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (needed < 0) {
        *restricted = 1;
        return NULL;
    }
    if (needed == 0) {
        return NULL;
    }
    struct proc_fdinfo *fds = (struct proc_fdinfo *)malloc((size_t)needed);
    if (!fds) {
        return NULL;
    }
    int got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, needed);
    if (got < 0) {
        *restricted = 1;
        free(fds);
        return NULL;
    }
    if (got == 0) {
        free(fds);
        return NULL;
    }
    *count = (size_t)got / sizeof(struct proc_fdinfo);
    return fds;
}

static void kb_classify_socket(const struct socket_fdinfo *info,
                               kb_socket_summary *summary)
{
    int family = info->psi.soi_family;
    int kind = info->psi.soi_kind;
    int type = info->psi.soi_type;
    int protocol = info->psi.soi_protocol;

    if (kind == SOCKINFO_TCP) {
        family = (info->psi.soi_proto.pri_tcp.tcpsi_ini.insi_vflag & INI_IPV6) ? 6 : 4;
    } else if (kind == SOCKINFO_IN) {
        family = (info->psi.soi_proto.pri_in.insi_vflag & INI_IPV6) ? 6 : 4;
    } else if (kind == SOCKINFO_UN) {
        family = AF_UNIX;
    } else if (family == AF_INET) {
        family = 4;
    } else if (family == AF_INET6) {
        family = 6;
    }

    switch (type) {
    case SOCK_STREAM: summary->stream++; break;
    case SOCK_DGRAM: summary->dgram++; break;
    case SOCK_RAW: summary->raw_type++; break;
    case SOCK_SEQPACKET: summary->seqpacket++; break;
    default: summary->other_type++; break;
    }

    if (family == AF_UNIX) {
        summary->unix_count++;
    } else if (family == 4 || family == 6) {
        if (type == SOCK_RAW || protocol == IPPROTO_RAW
            || (protocol != IPPROTO_TCP && protocol != IPPROTO_UDP)) {
            if (family == 6) {
                summary->raw6++;
            } else {
                summary->raw4++;
            }
        } else if (protocol == IPPROTO_TCP) {
            if (family == 6) {
                summary->tcp6++;
            } else {
                summary->tcp4++;
            }
        } else if (protocol == IPPROTO_UDP) {
            if (family == 6) {
                summary->udp6++;
            } else {
                summary->udp4++;
            }
        } else {
            summary->other++;
        }
    } else {
        summary->other++;
    }
    summary->total++;
}

int kb_socket_summary_all(const int32_t *pids, size_t pid_count,
                          kb_socket_summary **out, size_t *out_count)
{
    if (!out || !out_count) {
        return -1;
    }
    *out = NULL;
    *out_count = 0;
    if (pid_count == 0 || !pids) {
        return 0;
    }

    kb_socket_summary *items =
        (kb_socket_summary *)calloc(pid_count, sizeof(kb_socket_summary));
    if (!items) {
        return -1;
    }

    for (size_t i = 0; i < pid_count; i++) {
        int32_t pid = pids[i];
        kb_socket_summary *summary = &items[i];
        summary->pid = pid;
        if (pid <= 0) {
            summary->restricted = 1;
            continue;
        }

        size_t fd_count = 0;
        int restricted = 0;
        struct proc_fdinfo *fds =
            kb_open_fd_list_status(pid, &fd_count, &restricted);
        summary->restricted = restricted ? 1 : 0;
        if (!fds) {
            continue;
        }

        kb_token_set seen;
        if (kb_token_set_init(&seen, fd_count) != 0) {
            summary->truncated = 1;
            free(fds);
            continue;
        }

        for (size_t fd_index = 0; fd_index < fd_count; fd_index++) {
            if (fds[fd_index].proc_fdtype != PROX_FDTYPE_SOCKET) {
                continue;
            }

            struct socket_fdinfo info;
            memset(&info, 0, sizeof(info));
            int rc = proc_pidfdinfo(pid, fds[fd_index].proc_fd,
                                    PROC_PIDFDSOCKETINFO, &info,
                                    (int)sizeof(info));
            if (rc != (int)sizeof(info)) {
                continue;
            }

            summary->fds++;
            int inserted = kb_token_set_insert(&seen, info.psi.soi_so);
            if (inserted < 0) {
                summary->truncated = 1;
                break;
            }
            if (inserted == 0) {
                continue;
            }
            if (summary->total >= KB_SOCKET_MAX_UNIQUE) {
                summary->truncated = 1;
                break;
            }
            kb_classify_socket(&info, summary);
        }

        kb_token_set_free(&seen);
        free(fds);
    }

    *out = items;
    *out_count = pid_count;
    return 0;
}

void kb_socket_summary_free(kb_socket_summary *items)
{
    free(items);
}

int kb_open_file_list(int32_t pid, kb_open_file **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    size_t fd_count = 0;
    struct proc_fdinfo *fds = kb_open_fd_list(pid, &fd_count);
    if (!fds) {
        return -1;
    }

    kb_open_file *items = (kb_open_file *)calloc(fd_count ? fd_count : 1, sizeof(kb_open_file));
    if (!items) {
        free(fds);
        return -1;
    }

    size_t cursor = 0;
    for (size_t i = 0; i < fd_count; i++) {
        kb_open_file *item = &items[cursor++];
        item->fd = fds[i].proc_fd;
        item->type = fds[i].proc_fdtype;

        if (fds[i].proc_fdtype == PROX_FDTYPE_VNODE) {
            struct vnode_fdinfowithpath info;
            memset(&info, 0, sizeof(info));
            int rc = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO,
                                    &info, (int)sizeof(info));
            if (rc == (int)sizeof(info)) {
                strncpy(item->path, info.pvip.vip_path, sizeof(item->path) - 1);
                item->size = (uint64_t)info.pvip.vip_vi.vi_stat.vst_size;
            }
        }
    }

    free(fds);
    *out = items;
    *count = cursor;
    return 0;
}

void kb_open_file_list_free(kb_open_file *items)
{
    free(items);
}
