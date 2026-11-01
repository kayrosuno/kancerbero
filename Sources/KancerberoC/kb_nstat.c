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

/* Compact tombstones in batches: pruning walks the whole table, so doing it
   on every removal would make the callback path quadratic. */
#define KB_NSTAT_PRUNE_MIN_INACTIVE 32

typedef struct {
    kb_nstat_source_ref ref;
    kb_nstat_source sample;
    int active;
    /* Set by the removed block. Callbacks carry the entry source_id, so the
       flag mostly documents the intent; it also keeps a late counts callback
       from resurrecting a source the framework already reported as gone. */
    int removed;
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

    /* Serializes manager creation/teardown. Kept separate from g.mutex so a
       synchronous source callback during NStatManagerAddAll* cannot deadlock
       against the thread that is creating the manager. */
    pthread_mutex_t start_mutex;
    size_t start_refs;
    int subscribed_tcp;
    int subscribed_udp;

    pthread_mutex_t mutex;
    kb_entry *entries;
    size_t count;
    size_t capacity;
    size_t inactive;
    uint64_t next_source_id;

    int poll_active;
    size_t poll_pending;
    pthread_cond_t poll_cond;
} g = {
    .start_mutex = PTHREAD_MUTEX_INITIALIZER,
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
    pthread_mutex_lock(&g.start_mutex);
    if (g.opened) {
        pthread_mutex_unlock(&g.start_mutex);
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
        pthread_mutex_unlock(&g.start_mutex);
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
        g.handle = NULL;
        g.opened = 0;
        pthread_mutex_unlock(&g.start_mutex);
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
        g.handle = NULL;
        g.opened = 0;
        pthread_mutex_unlock(&g.start_mutex);
        return -1;
    }

    g.opened = 1;
    g.error[0] = '\0';
    pthread_mutex_unlock(&g.start_mutex);
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
    if (!entry || !dict || entry->removed) {
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

/* Callbacks match on (ref, source_id): the framework may recycle a released
   NStatSource pointer, and the token keeps a late callback from updating an
   unrelated entry that happens to reuse the address. */
static kb_entry *kb_find_token_locked(kb_nstat_source_ref ref, uint64_t token)
{
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].ref == ref && g.entries[i].sample.source_id == token) {
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

static void kb_on_description(kb_nstat_source_ref ref, uint64_t token,
                              CFDictionaryRef dict)
{
    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_token_locked(ref, token);
    if (entry) {
        kb_update_entry_locked(entry, dict, 0);
    }
    pthread_mutex_unlock(&g.mutex);
}

static void kb_on_counts(kb_nstat_source_ref ref, uint64_t token,
                         CFDictionaryRef dict)
{
    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_token_locked(ref, token);
    if (entry) {
        kb_update_entry_locked(entry, dict, 1);
    }
    /* Only counts callbacks complete a poll batch: kb_nstat_poll queries
       counts exclusively, so a description arriving on its own must not
       release a pending slot. */
    kb_note_poll_locked();
    pthread_mutex_unlock(&g.mutex);
}

/* Drops inactive entries and hands their refs to the caller, which must
   CFRelease them outside the mutex (releasing can run framework teardown).
   Skipped while a poll batch is in flight because the batch may still hold
   or query those refs. */
static size_t kb_prune_inactive_locked(kb_nstat_source_ref **dead_out)
{
    *dead_out = NULL;
    if (g.poll_active || g.inactive < KB_NSTAT_PRUNE_MIN_INACTIVE) {
        return 0;
    }
    kb_nstat_source_ref *dead =
        (kb_nstat_source_ref *)malloc(g.inactive * sizeof(*dead));
    if (!dead) {
        return 0;
    }
    size_t dead_count = 0;
    size_t write = 0;
    for (size_t i = 0; i < g.count; i++) {
        if (!g.entries[i].active) {
            dead[dead_count++] = g.entries[i].ref;
            continue;
        }
        if (write != i) {
            g.entries[write] = g.entries[i];
        }
        write++;
    }
    g.count = write;
    g.inactive = 0;
    *dead_out = dead;
    return dead_count;
}

static void kb_on_removed(kb_nstat_source_ref ref, uint64_t token)
{
    kb_nstat_source_ref *dead = NULL;
    size_t dead_count = 0;

    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_token_locked(ref, token);
    if (entry && !entry->removed) {
        entry->removed = 1;
        entry->active = 0;
        g.inactive++;
        dead_count = kb_prune_inactive_locked(&dead);
    }
    pthread_mutex_unlock(&g.mutex);

    for (size_t i = 0; i < dead_count; i++) {
        if (dead[i]) {
            CFRelease(dead[i]);
        }
    }
    free(dead);
}

static void kb_on_source(kb_nstat_source_ref ref)
{
    if (!ref) {
        return;
    }

    uint64_t token = 0;

    pthread_mutex_lock(&g.mutex);
    kb_entry *entry = kb_find_locked(ref);
    if (entry) {
        /* NetworkStatistics can announce the same source again (for example
           after an interface change). Reuse the entry instead of adding a
           duplicate row and keeping a second retain. */
        if (!entry->active && g.inactive > 0) {
            g.inactive--;
        }
        entry->active = 1;
        entry->removed = 0;
        token = entry->sample.source_id;
        pthread_mutex_unlock(&g.mutex);
    } else {
        if (kb_reserve_locked(g.count + 1) != 0) {
            pthread_mutex_unlock(&g.mutex);
            return;
        }
        entry = &g.entries[g.count++];
        memset(entry, 0, sizeof(*entry));
        entry->ref = ref;
        entry->active = 1;
        /* UUID is the process UUID, not a per-flow identifier: assign our own
           stable id so the UI can key rows uniquely. */
        entry->sample.source_id = ++g.next_source_id;
        token = entry->sample.source_id;
        CFRetain(ref);
        pthread_mutex_unlock(&g.mutex);
    }

    /* Re-registering is harmless for a reused source and replaces any blocks
       installed by a previous announcement. */
    g.set_description(ref, ^(CFDictionaryRef dict) {
        kb_on_description(ref, token, dict);
    });
    g.set_counts(ref, ^(CFDictionaryRef dict) {
        kb_on_counts(ref, token, dict);
    });
    if (g.set_removed) {
        g.set_removed(ref, ^{
            kb_on_removed(ref, token);
        });
    }

    g.query_description(ref);
    g.query_counts(ref);
}

int kb_nstat_start(int tcp, int udp)
{
    if (!tcp && !udp) {
        kb_set_error("no NetworkStatistics protocol requested");
        return -1;
    }
    if (!g.opened && kb_nstat_open() != 0) {
        return -1;
    }

    /* The manager lives for the whole process. NStatManager has no safe
       destroy path while its blocks may still fire, so creating a new one on
       every start (which is what happened when the daemon dropped a client
       connection) leaves the previous manager alive and makes it announce
       every flow a second time. */
    pthread_mutex_lock(&g.start_mutex);

    int ok = 1;
    if (g.manager) {
        if (tcp && !g.subscribed_tcp) {
            ok = g.add_tcp(g.manager, 0, 0) > 0;
            g.subscribed_tcp = ok;
        }
        if (ok && udp && !g.subscribed_udp) {
            ok = g.add_udp(g.manager, 0, 0) > 0;
            g.subscribed_udp = ok;
        }
    } else {
        g.queue = dispatch_queue_create("uno.kayros.kancerbero.nstat",
                                         DISPATCH_QUEUE_SERIAL);
        if (!g.queue) {
            kb_set_error("could not create NetworkStatistics queue");
            pthread_mutex_unlock(&g.start_mutex);
            return -1;
        }
        g.manager = g.create(kCFAllocatorDefault, g.queue,
                             ^(kb_nstat_source_ref ref, void *context) {
            (void)context;
            kb_on_source(ref);
        });
        if (!g.manager) {
            kb_set_error("NStatManagerCreate failed");
            pthread_mutex_unlock(&g.start_mutex);
            return -1;
        }
        g.set_flags(g.manager, 0);
        if (tcp) {
            ok = g.add_tcp(g.manager, 0, 0) > 0;
            g.subscribed_tcp = ok;
        }
        if (ok && udp) {
            ok = g.add_udp(g.manager, 0, 0) > 0;
            g.subscribed_udp = ok;
        }
    }

    if (!ok) {
        /* Keep the manager alive and the failed protocol flag cleared so the
           next start can retry the AddAll call on the same manager. */
        kb_set_error("NStatManagerAddAllTCP/UDPWithFilter failed");
        pthread_mutex_unlock(&g.start_mutex);
        return -1;
    }

    pthread_mutex_lock(&g.mutex);
    g.start_refs++;
    g.started = 1;
    g.error[0] = '\0';
    pthread_mutex_unlock(&g.mutex);
    pthread_mutex_unlock(&g.start_mutex);
    return 0;
}

int kb_nstat_poll(int timeout_ms)
{
    if (timeout_ms <= 0) {
        timeout_ms = 200;
    }

    pthread_mutex_lock(&g.mutex);
    if (!g.started || !g.manager || !g.queue) {
        pthread_mutex_unlock(&g.mutex);
        return -1;
    }
    if (g.poll_active) {
        /* Another caller owns the batch; the caller keeps the last known
           values and this tick is partial rather than failed. */
        pthread_mutex_unlock(&g.mutex);
        return 1;
    }

    /* Compact while no batch is in flight; the refs are released below,
       outside the mutex, because CFRelease may run framework teardown. */
    kb_nstat_source_ref *dead = NULL;
    size_t dead_count = kb_prune_inactive_locked(&dead);
    g.poll_active = 1;
    g.poll_pending = 0;
    pthread_mutex_unlock(&g.mutex);
    for (size_t i = 0; i < dead_count; i++) {
        if (dead[i]) {
            CFRelease(dead[i]);
        }
    }
    free(dead);

    pthread_mutex_lock(&g.mutex);
    if (!g.started) {
        g.poll_active = 0;
        pthread_mutex_unlock(&g.mutex);
        return 1;
    }
    /* Only live sources are queried. Dead entries used to be queried forever,
       which made memory and CPU grow with every flow the process ever saw. */
    size_t count = 0;
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].active && !g.entries[i].removed) {
            count++;
        }
    }
    if (count == 0) {
        g.poll_active = 0;
        g.poll_pending = 0;
        pthread_mutex_unlock(&g.mutex);
        return 0;
    }
    kb_nstat_source_ref *refs =
        (kb_nstat_source_ref *)malloc(count * sizeof(kb_nstat_source_ref));
    if (!refs) {
        g.poll_active = 0;
        pthread_mutex_unlock(&g.mutex);
        return -1;
    }
    size_t cursor = 0;
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].active && !g.entries[i].removed) {
            /* The batch owns one retain until it finishes: pruning is skipped
               while poll_active is set, but a source can still be released by
               the framework, and the query below must not use a dead ref. */
            kb_nstat_source_ref ref = g.entries[i].ref;
            CFRetain(ref);
            refs[cursor++] = ref;
        }
    }
    g.poll_pending = count;
    pthread_mutex_unlock(&g.mutex);

    dispatch_async(g.queue, ^{
        /* Identity, endpoints and TCP state only change in the source
           description, and NetworkStatistics does not push a new one by
           itself: counts keep returning the description cached when the
           source was announced. Ask for it on every tick, before the counts,
           so the snapshot of this tick already sees transitions such as
           SynSent -> Established. Description callbacks do not complete the
           poll batch; only counts do. */
        for (size_t i = 0; i < count; i++) {
            g.query_description(refs[i]);
        }
        for (size_t i = 0; i < count; i++) {
            g.query_counts(refs[i]);
        }

        /* The batch belongs to this block: the caller may have timed out and
           returned while these queries were still running, so neither the
           retained sources nor the array can be released there. */
        for (size_t i = 0; i < count; i++) {
            CFRelease(refs[i]);
        }
        free(refs);

        /* The block also owns the poll claim, so a late callback cannot
           complete a newer batch and no two batches overlap. */
        pthread_mutex_lock(&g.mutex);
        g.poll_active = 0;
        g.poll_pending = 0;
        pthread_cond_broadcast(&g.poll_cond);
        pthread_mutex_unlock(&g.mutex);
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
    /* The dispatch block releases the batch and clears the claim when it
       finishes; on a timeout the caller returns a partial result while the
       next polls report busy. Never release refs or reset the claim here. */
    pthread_mutex_unlock(&g.mutex);

    return timed_out ? 1 : 0;
}

size_t kb_nstat_source_count(void)
{
    pthread_mutex_lock(&g.mutex);
    size_t count = 0;
    for (size_t i = 0; i < g.count; i++) {
        if (g.entries[i].active && !g.entries[i].removed) {
            count++;
        }
    }
    pthread_mutex_unlock(&g.mutex);
    return count;
}

static size_t kb_addr_length(uint8_t family)
{
    if (family == 4) {
        return 4;
    }
    if (family == 6) {
        return 16;
    }
    return 0;
}

static int kb_compare_u64(uint64_t a, uint64_t b)
{
    return a < b ? -1 : (a > b ? 1 : 0);
}

static int kb_compare_u32(uint32_t a, uint32_t b)
{
    return a < b ? -1 : (a > b ? 1 : 0);
}

static int kb_compare_u16(uint16_t a, uint16_t b)
{
    return a < b ? -1 : (a > b ? 1 : 0);
}

static int kb_compare_i32(int32_t a, int32_t b)
{
    return a < b ? -1 : (a > b ? 1 : 0);
}

static int kb_compare_bytes(const uint8_t *a, const uint8_t *b, size_t length)
{
    if (length == 0) {
        return 0;
    }
    int result = memcmp(a, b, length);
    return result < 0 ? -1 : (result > 0 ? 1 : 0);
}

/* Unbound sockets report wildcard endpoints (0.0.0.0:0) and a process can
   legitimately hold dozens of them. Only entries with a concrete port are
   candidates for collapsing; two live TCP sockets can never share a full
   tuple, so such a collision means the same flow was announced twice. */
static int kb_flow_eligible(const kb_nstat_source *sample)
{
    return sample->local_port != 0 || sample->remote_port != 0;
}

static int kb_flow_compare(const void *lhs, const void *rhs)
{
    const kb_nstat_source *a = (const kb_nstat_source *)lhs;
    const kb_nstat_source *b = (const kb_nstat_source *)rhs;
    int a_eligible = kb_flow_eligible(a);
    int b_eligible = kb_flow_eligible(b);
    int result;

    if (a_eligible != b_eligible) {
        return a_eligible ? -1 : 1;
    }
    if (!a_eligible) {
        /* Ineligible entries are never merged; source_id keeps the order
           deterministic and unique. */
        return kb_compare_u64(a->source_id, b->source_id);
    }
    if ((result = kb_compare_i32(a->pid, b->pid)) != 0) return result;
    if ((result = kb_compare_i32(a->epid, b->epid)) != 0) return result;
    if ((result = strcmp(a->provider, b->provider)) != 0) return result < 0 ? -1 : 1;
    if ((result = kb_compare_u32(a->local_family, b->local_family)) != 0) return result;
    if ((result = kb_compare_bytes(a->local_addr, b->local_addr,
                                   kb_addr_length(a->local_family))) != 0) return result;
    if ((result = kb_compare_u16(a->local_port, b->local_port)) != 0) return result;
    if ((result = kb_compare_u32(a->local_scope, b->local_scope)) != 0) return result;
    if ((result = kb_compare_u32(a->remote_family, b->remote_family)) != 0) return result;
    if ((result = kb_compare_bytes(a->remote_addr, b->remote_addr,
                                   kb_addr_length(a->remote_family))) != 0) return result;
    if ((result = kb_compare_u16(a->remote_port, b->remote_port)) != 0) return result;
    if ((result = kb_compare_u32(a->remote_scope, b->remote_scope)) != 0) return result;
    if ((result = kb_compare_u64(a->start_ns, b->start_ns)) != 0) return result;
    return kb_compare_u64(a->source_id, b->source_id);
}

static int kb_flow_same(const kb_nstat_source *a, const kb_nstat_source *b)
{
    if (!kb_flow_eligible(a) || !kb_flow_eligible(b)) {
        return 0;
    }
    return a->pid == b->pid
        && a->epid == b->epid
        && strcmp(a->provider, b->provider) == 0
        && a->local_family == b->local_family
        && kb_compare_bytes(a->local_addr, b->local_addr,
                            kb_addr_length(a->local_family)) == 0
        && a->local_port == b->local_port
        && a->local_scope == b->local_scope
        && a->remote_family == b->remote_family
        && kb_compare_bytes(a->remote_addr, b->remote_addr,
                            kb_addr_length(a->remote_family)) == 0
        && a->remote_port == b->remote_port
        && a->remote_scope == b->remote_scope
        && a->start_ns == b->start_ns;
}

static uint64_t kb_max_u64(uint64_t a, uint64_t b)
{
    return a > b ? a : b;
}

static void kb_flow_merge(kb_nstat_source *into, const kb_nstat_source *from)
{
    into->rx_bytes = kb_max_u64(into->rx_bytes, from->rx_bytes);
    into->tx_bytes = kb_max_u64(into->tx_bytes, from->tx_bytes);
    into->rx_packets = kb_max_u64(into->rx_packets, from->rx_packets);
    into->tx_packets = kb_max_u64(into->tx_packets, from->tx_packets);
    into->rx_wifi = kb_max_u64(into->rx_wifi, from->rx_wifi);
    into->tx_wifi = kb_max_u64(into->tx_wifi, from->tx_wifi);
    into->rx_wired = kb_max_u64(into->rx_wired, from->rx_wired);
    into->tx_wired = kb_max_u64(into->tx_wired, from->tx_wired);
    into->rx_cellular = kb_max_u64(into->rx_cellular, from->rx_cellular);
    into->tx_cellular = kb_max_u64(into->tx_cellular, from->tx_cellular);
    into->rx_dupe = kb_max_u64(into->rx_dupe, from->rx_dupe);
    into->rx_ooo = kb_max_u64(into->rx_ooo, from->rx_ooo);
    into->tx_retx = kb_max_u64(into->tx_retx, from->tx_retx);
    into->has_splits = (uint8_t)(into->has_splits | from->has_splits);
}

/* Second line of defence: if the framework ever announces one flow as two
   sources with different refs, the UI must still show a single row. Entries
   are sorted by the flow key (source_id last), then each run collapses into
   its first element, which keeps the smallest source_id and therefore a
   stable identity for the rate dictionaries. */
static size_t kb_nstat_collapse_flows(kb_nstat_source *items, size_t count)
{
    qsort(items, count, sizeof(kb_nstat_source), kb_flow_compare);

    size_t write = 0;
    size_t read = 0;
    while (read < count) {
        size_t next = read + 1;
        if (kb_flow_eligible(&items[read])) {
            while (next < count && kb_flow_same(&items[read], &items[next])) {
                kb_flow_merge(&items[read], &items[next]);
                next++;
            }
        }
        if (write != read) {
            items[write] = items[read];
        }
        write++;
        read = next;
    }
    return write;
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
        if (g.entries[i].active && !g.entries[i].removed) {
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
            if (g.entries[i].active && !g.entries[i].removed) {
                items[cursor++] = g.entries[i].sample;
            }
        }
    }
    pthread_mutex_unlock(&g.mutex);

    if (active > 1) {
        active = kb_nstat_collapse_flows(items, active);
    }

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
    pthread_mutex_lock(&g.start_mutex);
    pthread_mutex_lock(&g.mutex);
    if (g.start_refs > 0) {
        g.start_refs--;
    }
    if (g.start_refs == 0) {
        g.started = 0;
        pthread_cond_broadcast(&g.poll_cond);
    }
    pthread_mutex_unlock(&g.mutex);
    pthread_mutex_unlock(&g.start_mutex);

    /* Deliberately non-destructive. NStatManager has no safe destroy path
       while its blocks may still fire, so the manager, queue, dlsym pointers
       and entry table live until the process exits. Freeing the entries here
       (as this function used to) released refs the leaked manager kept
       announcing, and the next kb_nstat_start() created a second live manager:
       every flow then arrived once per manager, which is what produced the
       duplicated rows in the Connections table. */
}

const char *kb_version(void)
{
    return "0.1.0";
}
