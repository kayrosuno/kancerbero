#include "KancerberoC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <arpa/inet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>

/* ------------------------------------------------------------------ */
/* Private NetworkStatistics types and symbols                         */
/* ------------------------------------------------------------------ */

typedef void *kb_nstat_manager;
typedef void *kb_nstat_source_ref;

typedef kb_nstat_manager (*kb_fn_manager_create)(CFAllocatorRef, dispatch_queue_t,
                                                 void (^)(kb_nstat_source_ref, void *));
typedef int (*kb_fn_manager_set_flags)(kb_nstat_manager, int);
typedef int (*kb_fn_add_all)(kb_nstat_manager, int, int);
typedef void (*kb_fn_set_description_block)(kb_nstat_source_ref, void (^)(CFDictionaryRef));
typedef void (*kb_fn_query_description)(kb_nstat_source_ref);
typedef void (*kb_fn_set_counts_block)(kb_nstat_source_ref, void (^)(CFDictionaryRef));
typedef void (*kb_fn_query_counts)(kb_nstat_source_ref);
typedef void (*kb_fn_set_removed_block)(kb_nstat_source_ref, void (^)(void));

typedef struct {
    kb_nstat_source_ref ref;
    kb_nstat_source sample;
    int active;
} kb_entry;

static struct {
    void *handle;
    int opened;
    int started;
    char error[256];

    kb_fn_manager_create create;
    kb_fn_manager_set_flags set_flags;
    kb_fn_add_all add_tcp;
    kb_fn_add_all add_udp;
    kb_fn_set_description_block set_description;
    kb_fn_query_description query_description;
    kb_fn_set_counts_block set_counts;
    kb_fn_query_counts query_counts;
    kb_fn_set_removed_block set_removed;

    CFStringRef k_pid;
    CFStringRef k_epid;
    CFStringRef k_name;
    CFStringRef k_provider;
    CFStringRef k_state;
    CFStringRef k_local;
    CFStringRef k_remote;
    CFStringRef k_ifindex;
    CFStringRef k_ifname;
    CFStringRef k_iftype;
    CFStringRef k_uuid;
    CFStringRef k_rx;
    CFStringRef k_tx;
    CFStringRef k_rxp;
    CFStringRef k_txp;
    CFStringRef k_rx_wifi;
    CFStringRef k_tx_wifi;
    CFStringRef k_rx_wired;
    CFStringRef k_tx_wired;
    CFStringRef k_rx_cell;
    CFStringRef k_tx_cell;
    CFStringRef k_rx_dupe;
    CFStringRef k_rx_ooo;
    CFStringRef k_tx_retx;
    CFStringRef k_rtt;
    CFStringRef k_start;

    dispatch_queue_t queue;
    kb_nstat_manager manager;

    pthread_mutex_t mutex;
    kb_entry *entries;
    size_t count;
    size_t capacity;

    int poll_active;
    size_t poll_pending;
    pthread_cond_t poll_cond;
} g = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .poll_cond = PTHREAD_COND_INITIALIZER,
};

static void kb_set_error(const char *message)
{
    snprintf(g.error, sizeof(g.error), "%s", message ? message : "unknown error");
}

static CFStringRef kb_key(void *handle, const char *name)
{
    CFStringRef *slot = (CFStringRef *)dlsym(handle, name);
    return slot ? *slot : NULL;
}

int kb_nstat_is_available(void)
{
    return g.opened && g.started;
}

const char *kb_nstat_last_error(void)
{
    return g.error;
}

int kb_nstat_open(void)
{
    if (g.opened) {
        return 0;
    }

    const char *paths[] = {
        "/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics",
        "/System/Library/PrivateFrameworks/NetworkStatistics.framework/Versions/A/NetworkStatistics",
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]) && !g.handle; i++) {
        g.handle = dlopen(paths[i], RTLD_LAZY | RTLD_GLOBAL);
    }
    if (!g.handle) {
        g.handle = dlopen(NULL, RTLD_LAZY);
    }
    if (!g.handle) {
        kb_set_error(dlerror());
        return -1;
    }

    g.create = (kb_fn_manager_create)dlsym(g.handle, "NStatManagerCreate");
    g.set_flags = (kb_fn_manager_set_flags)dlsym(g.handle, "NStatManagerSetFlags");
    g.add_tcp = (kb_fn_add_all)dlsym(g.handle, "NStatManagerAddAllTCPWithFilter");
    g.add_udp = (kb_fn_add_all)dlsym(g.handle, "NStatManagerAddAllUDPWithFilter");
    g.set_description = (kb_fn_set_description_block)dlsym(g.handle, "NStatSourceSetDescriptionBlock");
    g.query_description = (kb_fn_query_description)dlsym(g.handle, "NStatSourceQueryDescription");
    g.set_counts = (kb_fn_set_counts_block)dlsym(g.handle, "NStatSourceSetCountsBlock");
    g.query_counts = (kb_fn_query_counts)dlsym(g.handle, "NStatSourceQueryCounts");
    g.set_removed = (kb_fn_set_removed_block)dlsym(g.handle, "NStatSourceSetRemovedBlock");

    if (!g.create || !g.set_flags || !g.add_tcp || !g.add_udp ||
        !g.set_description || !g.query_description ||
        !g.set_counts || !g.query_counts) {
        kb_set_error("NetworkStatistics is missing required NStat symbols");
        dlclose(g.handle);
        memset(&g, 0, sizeof(g));
        pthread_mutex_init(&g.mutex, NULL);
        pthread_cond_init(&g.poll_cond, NULL);
        return -1;
    }

    g.k_pid = kb_key(g.handle, "kNStatSrcKeyPID");
    g.k_epid = kb_key(g.handle, "kNStatSrcKeyEPID");
    g.k_name = kb_key(g.handle, "kNStatSrcKeyProcessName");
    g.k_provider = kb_key(g.handle, "kNStatSrcKeyProvider");
    g.k_state = kb_key(g.handle, "kNStatSrcKeyTCPState");
    g.k_local = kb_key(g.handle, "kNStatSrcKeyLocal");
    g.k_remote = kb_key(g.handle, "kNStatSrcKeyRemote");
    g.k_ifindex = kb_key(g.handle, "kNStatSrcKeyInterface");
    g.k_ifname = kb_key(g.handle, "kNStatSrcKeyInterfaceName");
    g.k_iftype = kb_key(g.handle, "kNStatSrcKeyInterfaceType");
    g.k_uuid = kb_key(g.handle, "kNStatSrcKeyUUID");
    g.k_rx = kb_key(g.handle, "kNStatSrcKeyRxBytes");
    g.k_tx = kb_key(g.handle, "kNStatSrcKeyTxBytes");
    g.k_rxp = kb_key(g.handle, "kNStatSrcKeyRxPackets");
    g.k_txp = kb_key(g.handle, "kNStatSrcKeyTxPackets");
    g.k_rx_wifi = kb_key(g.handle, "kNStatSrcKeyRxWiFiBytes");
    g.k_tx_wifi = kb_key(g.handle, "kNStatSrcKeyTxWiFiBytes");
    g.k_rx_wired = kb_key(g.handle, "kNStatSrcKeyRxWiredBytes");
    g.k_tx_wired = kb_key(g.handle, "kNStatSrcKeyTxWiredBytes");
    g.k_rx_cell = kb_key(g.handle, "kNStatSrcKeyRxCellularBytes");
    g.k_tx_cell = kb_key(g.handle, "kNStatSrcKeyTxCellularBytes");
    g.k_rx_dupe = kb_key(g.handle, "kNStatSrcKeyRxDupeBytes");
    g.k_rx_ooo = kb_key(g.handle, "kNStatSrcKeyRxOOOBytes");
    g.k_tx_retx = kb_key(g.handle, "kNStatSrcKeyTxReTx");
    g.k_rtt = kb_key(g.handle, "kNStatSrcKeyAvgRTT");
    g.k_start = kb_key(g.handle, "kNStatSrcKeyStartAbsoluteTime");

    if (!g.k_pid) {
        kb_set_error("NetworkStatistics is missing kNStatSrcKeyPID");
        dlclose(g.handle);
        memset(&g, 0, sizeof(g));
        pthread_mutex_init(&g.mutex, NULL);
        pthread_cond_init(&g.poll_cond, NULL);
        return -1;
    }

    g.opened = 1;
    g.error[0] = '\0';
    return 0;
}

/* ------------------------------------------------------------------ */
/* Dictionary parsing                                                  */
/* ------------------------------------------------------------------ */

static void kb_read_string(CFDictionaryRef dict, CFStringRef key, char *buffer, size_t size)
{
    if (!dict || !key || !buffer || size == 0) {
        return;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
        return;
    }
    CFStringGetCString((CFStringRef)value, buffer, (CFIndex)size, kCFStringEncodingUTF8);
}

static void kb_read_uuid(CFDictionaryRef dict, CFStringRef key, char *buffer, size_t size)
{
    if (!dict || !key || !buffer || size == 0) {
        return;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (!value) {
        return;
    }
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)value, buffer, (CFIndex)size, kCFStringEncodingUTF8);
        return;
    }
    if (CFGetTypeID(value) == CFDataGetTypeID()) {
        CFDataRef data = (CFDataRef)value;
        CFIndex length = CFDataGetLength(data);
        const UInt8 *bytes = CFDataGetBytePtr(data);
        size_t written = 0;
        for (CFIndex i = 0; i < length && written + 2 < size; i++) {
            written += (size_t)snprintf(buffer + written, size - written, "%02x", bytes[i]);
        }
        buffer[written] = '\0';
    }
}

static int32_t kb_read_i32(CFDictionaryRef dict, CFStringRef key)
{
    if (!dict || !key) {
        return 0;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int32_t result = 0;
    CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &result);
    return result;
}

static uint64_t kb_read_u64(CFDictionaryRef dict, CFStringRef key)
{
    if (!dict || !key) {
        return 0;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int64_t result = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &result)) {
        return 0;
    }
    return result > 0 ? (uint64_t)result : 0;
}

static double kb_read_double(CFDictionaryRef dict, CFStringRef key)
{
    if (!dict || !key) {
        return 0.0;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0.0;
    }
    double result = 0.0;
    CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    return result;
}

static void kb_read_address(CFDictionaryRef dict, CFStringRef key,
                            uint8_t *family, uint8_t address[16],
                            uint16_t *port, uint32_t *scope)
{
    if (!dict || !key || !family || !address || !port || !scope) {
        return;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (!value || CFGetTypeID(value) != CFDataGetTypeID()) {
        return;
    }
    CFDataRef data = (CFDataRef)value;
    CFIndex length = CFDataGetLength(data);
    const struct sockaddr *sa = (const struct sockaddr *)CFDataGetBytePtr(data);
    if (length < (CFIndex)sizeof(struct sockaddr) || sa == NULL) {
        return;
    }
    if (sa->sa_family == AF_INET) {
        if (length < (CFIndex)sizeof(struct sockaddr_in)) {
            return;
        }
        const struct sockaddr_in *in = (const struct sockaddr_in *)sa;
        *family = 4;
        memcpy(address, &in->sin_addr, 4);
        *port = ntohs(in->sin_port);
        *scope = 0;
    } else if (sa->sa_family == AF_INET6) {
        if (length < (CFIndex)sizeof(struct sockaddr_in6)) {
            return;
        }
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)sa;
        *family = 6;
        memcpy(address, &in6->sin6_addr, 16);
        *port = ntohs(in6->sin6_port);
        *scope = in6->sin6_scope_id;
    }
}

/* Description dictionaries carry identity but zero byte counters. Counts
   dictionaries carry both. Preserve the last counters when merging a
   description-only update. */
static void kb_update_entry_locked(kb_entry *entry, CFDictionaryRef dict, int with_counters)
{
    if (!entry || !dict) {
        return;
    }
    kb_nstat_source merged = entry->sample;
    kb_nstat_source *sample = &merged;

    sample->pid = kb_read_i32(dict, g.k_pid);
    sample->epid = kb_read_i32(dict, g.k_epid);
    kb_read_string(dict, g.k_name, sample->process_name, sizeof(sample->process_name));
    kb_read_string(dict, g.k_provider, sample->provider, sizeof(sample->provider));
    kb_read_string(dict, g.k_state, sample->tcp_state, sizeof(sample->tcp_state));
    kb_read_string(dict, g.k_ifname, sample->if_name, sizeof(sample->if_name));
    if (sample->if_name[0] == '\0' && g.k_ifindex) {
        uint64_t index = kb_read_u64(dict, g.k_ifindex);
        if (index > 0 && index <= UINT32_MAX) {
            if_indextoname((unsigned int)index, sample->if_name);
        }
    }
    kb_read_string(dict, g.k_iftype, sample->if_type, sizeof(sample->if_type));
    kb_read_uuid(dict, g.k_uuid, sample->uuid, sizeof(sample->uuid));

    kb_read_address(dict, g.k_local, &sample->local_family, sample->local_addr,
                    &sample->local_port, &sample->local_scope);
    kb_read_address(dict, g.k_remote, &sample->remote_family, sample->remote_addr,
                    &sample->remote_port, &sample->remote_scope);

    if (with_counters) {
        sample->rx_bytes = kb_read_u64(dict, g.k_rx);
        sample->tx_bytes = kb_read_u64(dict, g.k_tx);
        sample->rx_packets = kb_read_u64(dict, g.k_rxp);
        sample->tx_packets = kb_read_u64(dict, g.k_txp);
        sample->rx_wifi = kb_read_u64(dict, g.k_rx_wifi);
        sample->tx_wifi = kb_read_u64(dict, g.k_tx_wifi);
        sample->rx_wired = kb_read_u64(dict, g.k_rx_wired);
        sample->tx_wired = kb_read_u64(dict, g.k_tx_wired);
        sample->rx_cellular = kb_read_u64(dict, g.k_rx_cell);
        sample->tx_cellular = kb_read_u64(dict, g.k_tx_cell);
        sample->rx_dupe = kb_read_u64(dict, g.k_rx_dupe);
        sample->rx_ooo = kb_read_u64(dict, g.k_rx_ooo);
        sample->tx_retx = kb_read_u64(dict, g.k_tx_retx);
        sample->rtt = kb_read_double(dict, g.k_rtt);
        sample->start_ns = kb_read_u64(dict, g.k_start);
        sample->has_splits = (g.k_rx_wifi || g.k_rx_wired || g.k_rx_cell) ? 1 : 0;
    }

    entry->sample = merged;
    entry->active = 1;
}

static kb_entry *kb_find_locked(kb_nstat_source_ref ref)
{
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].ref == ref) {
            return &g.entries[i];
        }
    }
    return NULL;
}

static int kb_reserve_locked(size_t needed)
{
    if (needed <= g.capacity) {
        return 0;
    }
    size_t capacity = g.capacity ? g.capacity : 64;
    while (capacity < needed) {
        capacity *= 2;
    }
    kb_entry *entries = (kb_entry *)realloc(g.entries, capacity * sizeof(kb_entry));
    if (!entries) {
        return -1;
    }
    g.entries = entries;
    g.capacity = capacity;
    return 0;
}

static void kb_note_poll_locked(void)
{
    if (g.poll_active && g.poll_pending > 0) {
        g.poll_pending--;
        if (g.poll_pending == 0) {
            pthread_cond_broadcast(&g.poll_cond);
        }
    }
}

static void kb_on_description(kb_nstat_source_ref ref, CFDictionaryRef dict)
{
    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_locked(ref);
    if (entry) {
        kb_update_entry_locked(entry, dict, 0);
    }
    kb_note_poll_locked();
    pthread_mutex_unlock(&g.mutex);
}

static void kb_on_counts(kb_nstat_source_ref ref, CFDictionaryRef dict)
{
    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_locked(ref);
    if (entry) {
        kb_update_entry_locked(entry, dict, 1);
    }
    kb_note_poll_locked();
    pthread_mutex_unlock(&g.mutex);
}

static void kb_on_removed(kb_nstat_source_ref ref)
{
    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_locked(ref);
    if (entry) {
        entry->active = 0;
    }
    kb_note_poll_locked();
    pthread_mutex_unlock(&g.mutex);
}

static void kb_on_source(kb_nstat_source_ref ref)
{
    if (!ref) {
        return;
    }
    CFRetain(ref);

    pthread_mutex_lock(&g.mutex);
    if (kb_reserve_locked(g.count + 1) != 0) {
        pthread_mutex_unlock(&g.mutex);
        CFRelease(ref);
        return;
    }
    kb_entry *entry = &g.entries[g.count++];
    memset(entry, 0, sizeof(*entry));
    entry->ref = ref;
    entry->active = 1;
    pthread_mutex_unlock(&g.mutex);

    g.set_description(ref, ^(CFDictionaryRef dict) {
        kb_on_description(ref, dict);
    });
    g.set_counts(ref, ^(CFDictionaryRef dict) {
        kb_on_counts(ref, dict);
    });
    if (g.set_removed) {
        g.set_removed(ref, ^{
            kb_on_removed(ref);
        });
    }
    g.query_description(ref);
    g.query_counts(ref);
}

int kb_nstat_start(int tcp, int udp)
{
    if (!g.opened && kb_nstat_open() != 0) {
        return -1;
    }
    if (g.started) {
        return 0;
    }

    g.queue = dispatch_queue_create("uno.kayros.kancerbero.nstat", DISPATCH_QUEUE_SERIAL);
    if (!g.queue) {
        kb_set_error("could not create NetworkStatistics queue");
        return -1;
    }

    g.manager = g.create(kCFAllocatorDefault, g.queue, ^(kb_nstat_source_ref ref, void *context) {
        (void)context;
        kb_on_source(ref);
    });
    if (!g.manager) {
        kb_set_error("NStatManagerCreate failed");
        return -1;
    }

    g.set_flags(g.manager, 0);
    int rc = 0;
    if (tcp) {
        rc = g.add_tcp(g.manager, 0, 0);
    }
    if (udp) {
        int rc2 = g.add_udp(g.manager, 0, 0);
        if (rc == 0) {
            rc = rc2;
        }
    }
    if (rc <= 0) {
        kb_set_error("NStatManagerAddAllTCP/UDPWithFilter failed");
        return -1;
    }

    g.started = 1;
    g.error[0] = '\0';
    return 0;
}

int kb_nstat_poll(int timeout_ms)
{
    if (!g.started || !g.queue) {
        return -1;
    }
    if (timeout_ms <= 0) {
        timeout_ms = 200;
    }

    pthread_mutex_lock(&g.mutex);
    size_t count = g.count;
    g.poll_active = 1;
    g.poll_pending = count;
    kb_nstat_source_ref *refs = NULL;
    if (count > 0) {
        refs = (kb_nstat_source_ref *)malloc(count * sizeof(kb_nstat_source_ref));
        if (!refs) {
            g.poll_active = 0;
            g.poll_pending = 0;
            pthread_mutex_unlock(&g.mutex);
            return -1;
        }
        for (size_t i = 0; i < count; i++) {
            refs[i] = g.entries[i].ref;
        }
    } else {
        pthread_cond_broadcast(&g.poll_cond);
    }
    pthread_mutex_unlock(&g.mutex);

    dispatch_async(g.queue, ^{
        for (size_t i = 0; i < count; i++) {
            g.query_counts(refs[i]);
        }
        free(refs);
    });

    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += timeout_ms / 1000;
    deadline.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }

    int timed_out = 0;
    pthread_mutex_lock(&g.mutex);
    while (g.poll_pending > 0) {
        int rc = pthread_cond_timedwait(&g.poll_cond, &g.mutex, &deadline);
        if (rc == ETIMEDOUT) {
            timed_out = 1;
            break;
        }
    }
    g.poll_active = 0;
    g.poll_pending = 0;
    pthread_mutex_unlock(&g.mutex);

    return timed_out ? 1 : 0;
}

size_t kb_nstat_source_count(void)
{
    pthread_mutex_lock(&g.mutex);
    size_t count = 0;
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].active) {
            count++;
        }
    }
    pthread_mutex_unlock(&g.mutex);
    return count;
}

int kb_nstat_snapshot(kb_nstat_source **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    pthread_mutex_lock(&g.mutex);
    size_t active = 0;
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].active) {
            active++;
        }
    }
    kb_nstat_source *items = NULL;
    if (active > 0) {
        items = (kb_nstat_source *)calloc(active, sizeof(kb_nstat_source));
        if (!items) {
            pthread_mutex_unlock(&g.mutex);
            return -1;
        }
        size_t cursor = 0;
        for (size_t i = 0; i < g.count; i++) {
            if (g.entries[i].active) {
                items[cursor++] = g.entries[i].sample;
            }
        }
    }
    pthread_mutex_unlock(&g.mutex);

    *out = items;
    *count = active;
    return 0;
}

void kb_nstat_snapshot_free(kb_nstat_source *sources)
{
    free(sources);
}

void kb_nstat_close(void)
{
    pthread_mutex_lock(&g.mutex);
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].ref) {
            CFRelease(g.entries[i].ref);
        }
    }
    free(g.entries);
    g.entries = NULL;
    g.count = 0;
    g.capacity = 0;
    g.started = 0;
    g.opened = 0;
    g.manager = NULL;
    g.queue = NULL;
    pthread_mutex_unlock(&g.mutex);
    /* The framework handle and the manager stay alive until process exit:
       tearing them down while blocks may still run is unsafe. */
}

const char *kb_version(void)
{
    return "0.1.0";
}
