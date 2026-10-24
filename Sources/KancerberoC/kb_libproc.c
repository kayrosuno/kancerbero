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
        struct proc_bsdinfo bsd;
        memset(&bsd, 0, sizeof(bsd));
        int rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, (int)sizeof(bsd));
        if (rc <= 0) {
            continue;
        }
        kb_process *item = &items[cursor++];
        item->pid = (int32_t)pid;
        item->ppid = (int32_t)bsd.pbi_ppid;
        item->uid = (uint32_t)bsd.pbi_uid;
        item->start_time_us = ((uint64_t)bsd.pbi_start_tvsec * 1000000ULL) +
                              (uint64_t)bsd.pbi_start_tvusec;
        const char *name = bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm;
        strncpy(item->name, name, sizeof(item->name) - 1);
        proc_pidpath(pid, item->path, (uint32_t)sizeof(item->path));
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
