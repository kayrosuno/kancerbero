#include "KancerberoC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <time.h>

/* CPU temperatures through the HID event system (IOHIDEventSystemClient).
   The symbols are exported by IOKit but live in private headers, so they are
   resolved with dlopen/dlsym like NetworkStatistics and libsystemstats.
   Apple silicon sensors are the same ones btop reads: eACC/pACC cluster
   probes, indexed "PMU tdie" die sensors and "SOC MTR Temp Sensor". */

#define KB_THERMAL_MAX_GROUPS 64
#define KB_THERMAL_EVENT_TYPE 15
#define KB_THERMAL_FIELD (KB_THERMAL_EVENT_TYPE << 16)
#define KB_THERMAL_REENUMERATE_MS 10000.0

typedef void *kb_hid_client;
typedef void *kb_hid_service;
typedef void *kb_hid_event;

typedef kb_hid_client (*kb_fn_client_create)(CFAllocatorRef);
typedef void (*kb_fn_set_matching)(kb_hid_client, CFDictionaryRef);
typedef CFArrayRef (*kb_fn_copy_services)(kb_hid_client);
typedef CFTypeRef (*kb_fn_copy_property)(kb_hid_service, CFStringRef);
typedef kb_hid_event (*kb_fn_copy_event)(kb_hid_service, int64_t, int32_t, int64_t);
typedef double (*kb_fn_get_float)(kb_hid_event, int32_t);

enum {
    KB_KIND_ACC = 0,
    KB_KIND_DIE = 1,
    KB_KIND_SOC = 2
};

typedef struct {
    kb_hid_service service;
    int group;
} kb_sensor;

typedef struct {
    int kind;
    int index;          /* PMU tdie index, -1 otherwise */
    CFStringRef name;   /* retained; cluster name for eACC/pACC */
    int count;
    double sum;
} kb_group;

typedef struct {
    int valid;
    int source;
    int package_valid;
    double package_celsius;
    int core_n;
    double core_means[KB_THERMAL_MAX_GROUPS];
    uint32_t sensor_count;
    uint32_t acc_count;
    uint32_t die_count;
    uint32_t soc_count;
} kb_cycle;

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static struct {
    int loaded;
    char error[256];

    kb_fn_client_create create_client;
    kb_fn_set_matching set_matching;
    kb_fn_copy_services copy_services;
    kb_fn_copy_property copy_property;
    kb_fn_copy_event copy_event;
    kb_fn_get_float get_float;

    kb_hid_client client;
    CFArrayRef services;
    kb_sensor *sensors;
    size_t sensor_count;
    kb_group groups[KB_THERMAL_MAX_GROUPS];
    int group_count;
    double last_enum_ms;

    kb_cycle cycle;
    double cycle_ms;
    int have_cycle;
    int tried_simple_client;
} g;

static void kb_thermal_set_error(const char *message)
{
    snprintf(g.error, sizeof(g.error), "%s", message);
}

static double kb_now_ms(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

static uint32_t kb_logical_cpu_count(void)
{
    int value = 0;
    size_t size = sizeof(value);
    if (sysctlbyname("hw.logicalcpu", &value, &size, NULL, 0) == 0 && value > 0) {
        return (uint32_t)value;
    }
    return 1;
}

static void *kb_symbol(void *handle, const char *name)
{
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (!symbol && handle) {
        symbol = dlsym(handle, name);
    }
    return symbol;
}

static void kb_thermal_load_once(void)
{
    g.create_client = NULL;
    g.set_matching = NULL;
    g.copy_services = NULL;
    g.copy_property = NULL;
    g.copy_event = NULL;
    g.get_float = NULL;

    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                          RTLD_LAZY | RTLD_LOCAL);

    g.create_client = (kb_fn_client_create)kb_symbol(
        handle, "IOHIDEventSystemClientCreate");
    g.set_matching = (kb_fn_set_matching)kb_symbol(
        handle, "IOHIDEventSystemClientSetMatching");
    g.copy_services = (kb_fn_copy_services)kb_symbol(
        handle, "IOHIDEventSystemClientCopyServices");
    g.copy_property = (kb_fn_copy_property)kb_symbol(
        handle, "IOHIDServiceClientCopyProperty");
    g.copy_event = (kb_fn_copy_event)kb_symbol(
        handle, "IOHIDServiceClientCopyEvent");
    g.get_float = (kb_fn_get_float)kb_symbol(
        handle, "IOHIDEventGetFloatValue");

    if (!g.copy_services || !g.copy_property || !g.copy_event || !g.get_float) {
        kb_thermal_set_error("IOHID temperature symbols unavailable");
        return;
    }
    if (!g.create_client) {
        /* Client creation without a usage filter is still usable: every
           service is classified by its Product property below. */
        g.create_client = (kb_fn_client_create)kb_symbol(
            handle, "IOHIDEventSystemClientCreateSimpleClient");
        g.tried_simple_client = 1;
        if (!g.create_client) {
            kb_thermal_set_error("no IOHID client factory");
            return;
        }
    }
    g.loaded = 1;
}

static void kb_thermal_release_locked(void)
{
    if (g.services) {
        CFRelease((CFTypeRef)g.services);
        g.services = NULL;
    }
    if (g.client) {
        CFRelease((CFTypeRef)g.client);
        g.client = NULL;
    }
    for (int i = 0; i < g.group_count; i++) {
        if (g.groups[i].name) {
            CFRelease((CFTypeRef)g.groups[i].name);
        }
    }
    g.group_count = 0;
    free(g.sensors);
    g.sensors = NULL;
    g.sensor_count = 0;
    g.have_cycle = 0;
}

static int kb_parse_die_index(const char *name, int *out_index)
{
    const char *cursor = name + strlen("PMU tdie");
    while (*cursor == ' ' || *cursor == '_' || *cursor == '-') {
        cursor++;
    }
    if (*cursor < '0' || *cursor > '9') {
        return 0;
    }
    int value = 0;
    while (*cursor >= '0' && *cursor <= '9') {
        value = value * 10 + (*cursor - '0');
        cursor++;
    }
    *out_index = value;
    return 1;
}

static int kb_group_for_locked(int kind, CFStringRef name, int index)
{
    for (int i = 0; i < g.group_count; i++) {
        kb_group *group = &g.groups[i];
        if (group->kind != kind) {
            continue;
        }
        if (kind == KB_KIND_SOC) {
            return i;
        }
        if (kind == KB_KIND_DIE && group->index == index) {
            return i;
        }
        if (kind == KB_KIND_ACC && group->name && name
            && CFStringCompare(group->name, name, 0) == kCFCompareEqualTo) {
            return i;
        }
    }
    if (g.group_count >= KB_THERMAL_MAX_GROUPS) {
        return -1;
    }
    kb_group *group = &g.groups[g.group_count];
    group->kind = kind;
    group->index = index;
    group->name = name ? (CFStringRef)CFRetain(name) : NULL;
    group->count = 0;
    group->sum = 0;
    return g.group_count++;
}

static int kb_thermal_prepare_locked(void)
{
    if (g.client && g.services) {
        return 1;
    }
    if (!g.loaded) {
        if (g.error[0] == '\0') {
            kb_thermal_set_error("IOHID temperature unavailable");
        }
        return -1;
    }

    int page = 0xff00;
    int usage = 5;
    CFNumberRef page_ref = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usage_ref = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!page_ref || !usage_ref || !match) {
        if (page_ref) CFRelease(page_ref);
        if (usage_ref) CFRelease(usage_ref);
        if (match) CFRelease(match);
        kb_thermal_set_error("could not build IOHID match");
        return -1;
    }
    CFDictionarySetValue(match, CFSTR("PrimaryUsagePage"), page_ref);
    CFDictionarySetValue(match, CFSTR("PrimaryUsage"), usage_ref);
    CFRelease(page_ref);
    CFRelease(usage_ref);

    g.client = g.create_client(kCFAllocatorDefault);
    if (g.client && g.set_matching && !g.tried_simple_client) {
        g.set_matching(g.client, match);
    }
    CFRelease(match);
    if (!g.client) {
        kb_thermal_set_error("could not create IOHID event client");
        return -1;
    }

    g.services = g.copy_services(g.client);
    if (!g.services) {
        kb_thermal_set_error("could not copy IOHID services");
        kb_thermal_release_locked();
        return -1;
    }

    CFIndex count = CFArrayGetCount(g.services);
    if (count <= 0) {
        kb_thermal_set_error("no IOHID services");
        return 1;
    }
    g.sensors = calloc((size_t)count, sizeof(kb_sensor));
    if (!g.sensors) {
        kb_thermal_set_error("out of memory");
        kb_thermal_release_locked();
        return -1;
    }

    for (CFIndex i = 0; i < count; i++) {
        kb_hid_service service =
            (kb_hid_service)CFArrayGetValueAtIndex(g.services, i);
        CFTypeRef product = g.copy_property(service, CFSTR("Product"));
        if (!product) {
            continue;
        }
        if (CFGetTypeID(product) != CFStringGetTypeID()) {
            CFRelease(product);
            continue;
        }
        char name[128] = {0};
        if (!CFStringGetCString((CFStringRef)product, name, sizeof(name),
                                kCFStringEncodingUTF8)) {
            CFRelease(product);
            continue;
        }

        int kind = -1;
        int index = -1;
        if (strncmp(name, "eACC", 4) == 0 || strncmp(name, "pACC", 4) == 0) {
            kind = KB_KIND_ACC;
        } else if (strncmp(name, "PMU tdie", 8) == 0) {
            kind = KB_KIND_DIE;
            if (!kb_parse_die_index(name, &index)) {
                index = -1;
            }
        } else if (strncmp(name, "SOC MTR Temp Sensor", 19) == 0) {
            kind = KB_KIND_SOC;
        }

        if (kind >= 0) {
            int group = kb_group_for_locked(kind, (CFStringRef)product, index);
            if (group >= 0) {
                g.sensors[g.sensor_count].service = service;
                g.sensors[g.sensor_count].group = group;
                g.sensor_count++;
            }
        }
        CFRelease(product);
    }

    g.last_enum_ms = kb_now_ms();
    if (g.sensor_count == 0) {
        kb_thermal_set_error("no CPU temperature sensors");
        return 1;
    }
    return 1;
}

static void kb_sort_group_indices(int *indices, int count, int by_index,
                                  int ascending)
{
    for (int i = 1; i < count; i++) {
        int value = indices[i];
        int j = i - 1;
        while (j >= 0) {
            int other = indices[j];
            int comparison;
            if (by_index) {
                comparison = (g.groups[value].index < g.groups[other].index) ? -1
                           : (g.groups[value].index > g.groups[other].index) ? 1 : 0;
            } else {
                comparison = g.groups[value].name && g.groups[other].name
                    ? (int)CFStringCompare(g.groups[value].name,
                                           g.groups[other].name,
                                           0)
                    : 0;
            }
            if (!ascending) {
                comparison = -comparison;
            }
            if (comparison >= 0) {
                break;
            }
            indices[j + 1] = other;
            j--;
        }
        indices[j + 1] = value;
    }
}

static double kb_mean(const int *indices, int count)
{
    double sum = 0;
    int readings = 0;
    for (int i = 0; i < count; i++) {
        const kb_group *group = &g.groups[indices[i]];
        sum += group->sum;
        readings += group->count;
    }
    return readings > 0 ? sum / (double)readings : 0;
}

static void kb_read_cycle_locked(kb_cycle *out)
{
    memset(out, 0, sizeof(*out));
    out->source = KB_THERMAL_SOURCE_NONE;
    if (kb_thermal_prepare_locked() != 1 || g.sensor_count == 0) {
        return;
    }

    for (int i = 0; i < g.group_count; i++) {
        g.groups[i].count = 0;
        g.groups[i].sum = 0;
    }

    for (size_t i = 0; i < g.sensor_count; i++) {
        kb_hid_event event = g.copy_event(g.sensors[i].service,
                                          KB_THERMAL_EVENT_TYPE, 0, 0);
        if (!event) {
            continue;
        }
        double celsius = g.get_float(event, (int32_t)KB_THERMAL_FIELD);
        CFRelease((CFTypeRef)event);
        if (!(celsius > 0.0 && celsius < 150.0)) {
            continue;
        }
        kb_group *group = &g.groups[g.sensors[i].group];
        group->sum += celsius;
        group->count++;
        out->sensor_count++;
    }

    int acc_indices[KB_THERMAL_MAX_GROUPS];
    int die_indices[KB_THERMAL_MAX_GROUPS];
    int soc_indices[KB_THERMAL_MAX_GROUPS];
    int acc_n = 0, die_n = 0, soc_n = 0;
    for (int i = 0; i < g.group_count; i++) {
        if (g.groups[i].count == 0) {
            continue;
        }
        switch (g.groups[i].kind) {
        case KB_KIND_ACC: acc_indices[acc_n++] = i; break;
        case KB_KIND_DIE: die_indices[die_n++] = i; break;
        case KB_KIND_SOC: soc_indices[soc_n++] = i; break;
        default: break;
        }
    }
    kb_sort_group_indices(die_indices, die_n, 1, 1);
    kb_sort_group_indices(acc_indices, acc_n, 0, 1);

    out->acc_count = (uint32_t)acc_n;
    out->die_count = (uint32_t)die_n;
    out->soc_count = (uint32_t)soc_n;

    const int *core_groups = die_n > 0 ? die_indices : acc_indices;
    int core_n = die_n > 0 ? die_n : acc_n;
    for (int i = 0; i < core_n && i < KB_THERMAL_MAX_GROUPS; i++) {
        out->core_means[i] = g.groups[core_groups[i]].sum /
                             (double)g.groups[core_groups[i]].count;
    }
    out->core_n = core_n;

    if (acc_n > 0) {
        out->package_celsius = kb_mean(acc_indices, acc_n);
        out->package_valid = 1;
        out->source = KB_THERMAL_SOURCE_ACC;
    } else if (die_n > 0) {
        out->package_celsius = kb_mean(die_indices, die_n);
        out->package_valid = 1;
        out->source = KB_THERMAL_SOURCE_DIE;
    } else if (soc_n > 0) {
        out->package_celsius = kb_mean(soc_indices, soc_n);
        out->package_valid = 1;
        out->source = KB_THERMAL_SOURCE_SOC;
    }

    out->valid = out->package_valid || out->core_n > 0;
}

static void kb_fill_out_locked(const kb_cycle *cycle, uint32_t core_count,
                               kb_thermal_stats *out)
{
    memset(out, 0, sizeof(*out));
    out->valid = cycle->valid;
    out->source = cycle->source;
    out->package_valid = cycle->package_valid;
    out->package_celsius = cycle->package_celsius;
    out->core_count = core_count;
    out->core_temp_sensors = (uint32_t)cycle->core_n;
    out->sensor_count = cycle->sensor_count;
    out->cluster_count = cycle->acc_count;
    out->die_count = cycle->die_count;
    out->soc_count = cycle->soc_count;
    for (uint32_t i = 0; i < KB_MAX_CORES; i++) {
        out->core_celsius[i] = -1.0;
    }
    if (core_count == 0 || cycle->core_n <= 0) {
        return;
    }
    uint32_t sensors = (uint32_t)cycle->core_n;
    for (uint32_t core = 0; core < core_count; core++) {
        uint32_t index = (uint32_t)(((uint64_t)core * sensors) / core_count);
        if (index >= sensors) {
            index = sensors - 1;
        }
        out->core_celsius[core] = cycle->core_means[index];
    }
}

int kb_thermal_stats_read(kb_thermal_stats *out, uint32_t core_count,
                          uint32_t min_interval_ms)
{
    if (!out) {
        return -1;
    }
    pthread_once(&g_once, kb_thermal_load_once);
    pthread_mutex_lock(&g_lock);

    if (!g.loaded) {
        kb_fill_out_locked(&(kb_cycle){0}, 0, out);
        pthread_mutex_unlock(&g_lock);
        return -1;
    }

    if (core_count == 0) {
        core_count = kb_logical_cpu_count();
    }
    if (core_count > KB_MAX_CORES) {
        core_count = KB_MAX_CORES;
    }

    double now = kb_now_ms();
    int expired = !g.have_cycle
        || (min_interval_ms == 0)
        || ((now - g.cycle_ms) >= (double)min_interval_ms);
    if (expired) {
        kb_read_cycle_locked(&g.cycle);
        g.cycle_ms = now;
        g.have_cycle = 1;
        if (!g.cycle.valid && (now - g.last_enum_ms) >= KB_THERMAL_REENUMERATE_MS) {
            kb_thermal_release_locked();
            kb_read_cycle_locked(&g.cycle);
            g.cycle_ms = now;
            g.have_cycle = 1;
        }
    }

    kb_fill_out_locked(&g.cycle, core_count, out);
    int result = g.cycle.valid ? 0 : -1;
    pthread_mutex_unlock(&g_lock);
    return result;
}

int kb_thermal_is_available(void)
{
    kb_thermal_stats stats;
    return kb_thermal_stats_read(&stats, 0, 0) == 0 && stats.valid != 0;
}

const char *kb_thermal_last_error(void)
{
    return g.error[0] ? g.error : "unavailable";
}

void kb_thermal_reset(void)
{
    pthread_once(&g_once, kb_thermal_load_once);
    pthread_mutex_lock(&g_lock);
    kb_thermal_release_locked();
    g.cycle_ms = 0;
    pthread_mutex_unlock(&g_lock);
}
