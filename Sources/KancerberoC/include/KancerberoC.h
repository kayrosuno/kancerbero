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
/* Identity-only KERN_PROC_ALL list (no task/energy counters). */
int kb_process_metadata_list(kb_process **out, size_t *count);
void kb_process_list_free(kb_process *items);
/* Returns the path length, or -1 when unavailable. */
int kb_process_path(int32_t pid, char *buffer, size_t size);

/* Per-process socket descriptors (same uid unless root). */
int kb_socket_list(int32_t pid, kb_socket **out, size_t *count);
void kb_socket_list_free(kb_socket *items);

/* Aggregated socket counts per PID (same uid unless root). */
int kb_socket_summary_all(const int32_t *pids, size_t pid_count,
                          kb_socket_summary **out, size_t *out_count);
void kb_socket_summary_free(kb_socket_summary *items);

/* Per-process open descriptors with paths when available. */
int kb_open_file_list(int32_t pid, kb_open_file **out, size_t *count);
void kb_open_file_list_free(kb_open_file *items);

/* sysctl NET_RT_IFLIST2 interface counters. */
int kb_interface_list(kb_interface **out, size_t *count);
void kb_interface_list_free(kb_interface *items);

int kb_sysctl_int(const char *name, int *value);

/* CPU cores, memory, swap, load average and boot time. */
int kb_host_stats_read(kb_host_stats *out);
/* Host-wide memory pressure, as Activity Monitor reports it. Fills the
   pressure percentage (100 - free %) and the kernel level (1/2/4). */
int kb_memory_pressure_read(int32_t *percent, int32_t *level);
/* GPU utilisation and memory from IOAccelerator PerformanceStatistics. */
int kb_gpu_stats_read(kb_gpu_stats *out);
/* Battery charge, time remaining and power source. */
int kb_power_stats_read(kb_power_stats *out);
/* 12-hour charge graph from libsystemstats (private), loaded with dlopen.
   Returns 1 on success; caller frees with kb_battery_charge_graph_free. */
int kb_battery_charge_graph_read(kb_battery_charge_graph *out);
void kb_battery_charge_graph_free(kb_battery_charge_graph *graph);
/* Per-process energy and wake-up counters from rusage_info_v6. */
int kb_process_energy_read(int32_t pid, uint64_t *energy_nj,
                           uint64_t *interrupt_wkups, uint64_t *pkg_idle_wkups);
/* Per-process disk counters from rusage_info_v6. */
int kb_process_io_read(int32_t pid, uint64_t *bytes_read,
                       uint64_t *bytes_written, uint64_t *logical_writes);
/* PIDs holding an active PreventUserIdleSystemSleep/PreventSystemSleep
   assertion. Caller frees `pids` with free(). */
int kb_prevent_sleep_pids(int32_t **pids, size_t *count);
/* Cumulative bytes and operations across IOBlockStorageDriver services. */
int kb_disk_io_read(uint64_t *bytes_read, uint64_t *bytes_written,
                    uint64_t *read_ops, uint64_t *write_ops);

#ifdef __cplusplus
}
#endif

#endif
