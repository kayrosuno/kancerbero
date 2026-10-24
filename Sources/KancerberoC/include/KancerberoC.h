#ifndef KANCERBERO_C_H
#define KANCERBERO_C_H

#include "KBModels.h"
#include "KBLaunchd.h"
#include "KBDisk.h"

#ifdef __cplusplus
extern "C" {
#endif

const char *kb_version(void);

/* NetworkStatistics.framework (private), loaded with dlopen. */
int kb_nstat_open(void);
void kb_nstat_close(void);
int kb_nstat_is_available(void);
const char *kb_nstat_last_error(void);
int kb_nstat_start(int tcp, int udp);
/* Returns 0 on success, 1 on timeout, -1 on failure. */
int kb_nstat_poll(int timeout_ms);
int kb_nstat_snapshot(kb_nstat_source **out, size_t *count);
void kb_nstat_snapshot_free(kb_nstat_source *sources);
size_t kb_nstat_source_count(void);

/* libproc-based inventory (same uid unless root). */
int kb_process_list(kb_process **out, size_t *count);
void kb_process_list_free(kb_process *items);
/* Returns the path length, or -1 when unavailable. */
int kb_process_path(int32_t pid, char *buffer, size_t size);

/* Per-process socket descriptors (same uid unless root). */
int kb_socket_list(int32_t pid, kb_socket **out, size_t *count);
void kb_socket_list_free(kb_socket *items);

/* Per-process open descriptors with paths when available. */
int kb_open_file_list(int32_t pid, kb_open_file **out, size_t *count);
void kb_open_file_list_free(kb_open_file *items);

/* sysctl NET_RT_IFLIST2 interface counters. */
int kb_interface_list(kb_interface **out, size_t *count);
void kb_interface_list_free(kb_interface *items);

int kb_sysctl_int(const char *name, int *value);

#ifdef __cplusplus
}
#endif

#endif
