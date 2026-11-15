#include "KancerberoC.h"

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/machine.h>
#include <mach/processor_info.h>
#include <mach/vm_statistics.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/storage/IOBlockStorageDriver.h>

/*
 * Exported by libsystem_kernel and used by Activity Monitor. It fills the
 * system-wide memory free percentage (0-100); it takes no port argument.
 */
extern int memorystatus_get_level(int *level);

/*
 * Interface counters come from the IFMIB sysctl, not NET_RT_IFLIST2.
 * On macOS 27 the NET_RT_IFLIST2 path returns if_data64 with only the low
 * 32 bits of ifi_ibytes/ifi_obytes populated (verified against netstat),
 * while net.link.generic.ifdata returns the full 64-bit values.
 */
int kb_interface_list(kb_interface **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    int name[16];
    size_t name_length = sizeof(name) / sizeof(name[0]);
    if (sysctlnametomib("net.link.generic.system.ifcount", name, &name_length) != 0) {
        return -1;
    }
    if (name_length < 5) {
        return -1;
    }

    int interface_count = 0;
    size_t count_length = sizeof(interface_count);
    if (sysctl(name, (u_int)name_length, &interface_count, &count_length, NULL, 0) != 0) {
        return -1;
    }
    if (interface_count <= 0) {
        return -1;
    }

    kb_interface *items = (kb_interface *)calloc((size_t)interface_count, sizeof(kb_interface));
    if (!items) {
        return -1;
    }

    size_t cursor = 0;
    for (int index = 1; index <= interface_count; index++) {
        int mib[8];
        memcpy(mib, name, sizeof(int) * name_length);
        mib[3] = IFMIB_IFDATA;
        mib[4] = index;
        mib[5] = IFDATA_GENERAL;

        struct ifmibdata data;
        size_t length = sizeof(data);
        memset(&data, 0, sizeof(data));
        if (sysctl(mib, 6, &data, &length, NULL, 0) != 0) {
            continue;
        }

        kb_interface *item = &items[cursor++];
        item->index = (uint32_t)index;
        strncpy(item->name, data.ifmd_name, sizeof(item->name) - 1);
        item->flags = data.ifmd_flags;
        item->type = data.ifmd_data.ifi_type;
        item->rx_bytes = data.ifmd_data.ifi_ibytes;
        item->tx_bytes = data.ifmd_data.ifi_obytes;
        item->rx_packets = data.ifmd_data.ifi_ipackets;
        item->tx_packets = data.ifmd_data.ifi_opackets;
        item->rx_errors = data.ifmd_data.ifi_ierrors;
        item->tx_errors = data.ifmd_data.ifi_oerrors;
        item->rx_drops = data.ifmd_data.ifi_iqdrops;
        item->collisions = data.ifmd_data.ifi_collisions;
        item->mtu = data.ifmd_data.ifi_mtu;
        item->baudrate = data.ifmd_data.ifi_baudrate;
    }

    *out = items;
    *count = cursor;
    return 0;
}

void kb_interface_list_free(kb_interface *items)
{
    free(items);
}

int kb_sysctl_int(const char *name, int *value)
{
    if (!name || !value) {
        return -1;
    }
    size_t length = sizeof(*value);
    return sysctlbyname(name, value, &length, NULL, 0);
}

int kb_memory_pressure_read(int32_t *percent, int32_t *level)
{
    if (!percent || !level) {
        return -1;
    }

    int free_percent = -1;
    if (memorystatus_get_level(&free_percent) != 0) {
        return -1;
    }
    *percent = (int32_t)(100 - free_percent);

    int vm_level = 0;
    size_t level_size = sizeof(vm_level);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &vm_level,
                     &level_size, NULL, 0) == 0) {
        *level = (int32_t)vm_level;
    } else {
        *level = -1;
    }
    return 0;
}

static double kb_cf_double(CFDictionaryRef dictionary, CFStringRef key)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return -1;
    }
    double result = -1;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result)) {
        return -1;
    }
    return result;
}

static uint64_t kb_cf_u64(CFDictionaryRef dictionary, CFStringRef key)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int64_t result = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &result)) {
        return 0;
    }
    return result < 0 ? 0 : (uint64_t)result;
}

int kb_gpu_stats_read(kb_gpu_stats *out)
{
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->utilization_percent = -1;
    out->renderer_percent = -1;
    out->tiler_percent = -1;

    size_t name_length = sizeof(out->name);
    if (sysctlbyname("machdep.cpu.brand_string", out->name, &name_length,
                     NULL, 0) != 0) {
        out->name[0] = '\0';
    }

    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                     IOServiceMatching("IOAccelerator"),
                                     &iterator) != KERN_SUCCESS) {
        return -1;
    }

    io_service_t service = 0;
    while ((service = IOIteratorNext(iterator)) != 0) {
        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(service, &properties,
                                              kCFAllocatorDefault, 0) == KERN_SUCCESS
            && properties) {
            CFTypeRef statistics =
                CFDictionaryGetValue(properties, CFSTR("PerformanceStatistics"));
            if (statistics && CFGetTypeID(statistics) == CFDictionaryGetTypeID()) {
                CFDictionaryRef dictionary = (CFDictionaryRef)statistics;
                out->utilization_percent =
                    kb_cf_double(dictionary, CFSTR("Device Utilization %"));
                out->renderer_percent =
                    kb_cf_double(dictionary, CFSTR("Renderer Utilization %"));
                out->tiler_percent =
                    kb_cf_double(dictionary, CFSTR("Tiler Utilization %"));
                out->in_use_memory =
                    kb_cf_u64(dictionary, CFSTR("In use system memory"));
                out->alloc_memory =
                    kb_cf_u64(dictionary, CFSTR("Alloc system memory"));
                out->valid = 1;
            }
            CFRelease(properties);
        }
        IOObjectRelease(service);
        if (out->valid) {
            break;
        }
    }
    IOObjectRelease(iterator);
    return out->valid ? 0 : -1;
}

/*
 * Per-process GPU time lives on the IOAccelerator user clients (for example
 * AGXDeviceUserClient): IOUserClientCreator holds "pid N, name" and AppUsage
 * is an array of dictionaries with a cumulative accumulatedGPUTime in
 * nanoseconds. These entries are not registered services, so a direct
 * IOServiceMatching does not find them; the accelerator subtree must be
 * walked with IORegistryEntryCreateIterator. Readable without privileges.
 */
typedef struct {
    kb_gpu_process *items;
    size_t count;
    size_t capacity;
} kb_gpu_accumulator;

static uint64_t kb_gpu_saturating_add(uint64_t a, uint64_t b)
{
    return a > UINT64_MAX - b ? UINT64_MAX : a + b;
}

static int32_t kb_gpu_pid_from_creator(CFTypeRef value)
{
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
        return 0;
    }
    CFStringRef string = (CFStringRef)value;
    CFIndex length = CFStringGetLength(string);
    if (length < 5) {
        return 0;
    }
    if (CFStringGetCharacterAtIndex(string, 0) != 'p'
        || CFStringGetCharacterAtIndex(string, 1) != 'i'
        || CFStringGetCharacterAtIndex(string, 2) != 'd'
        || CFStringGetCharacterAtIndex(string, 3) != ' ') {
        return 0;
    }
    int64_t pid = 0;
    int digits = 0;
    for (CFIndex index = 4; index < length; index++) {
        UniChar character = CFStringGetCharacterAtIndex(string, index);
        if (character < '0' || character > '9') {
            break;
        }
        if (pid > (INT32_MAX - (character - '0')) / 10) {
            return 0;
        }
        pid = pid * 10 + (character - '0');
        digits++;
    }
    if (digits == 0 || pid <= 0 || pid > INT32_MAX) {
        return 0;
    }
    return (int32_t)pid;
}

static uint64_t kb_gpu_app_usage_sum(CFTypeRef usage)
{
    if (!usage) {
        return 0;
    }
    uint64_t total = 0;
    CFTypeID type = CFGetTypeID(usage);
    if (type == CFArrayGetTypeID()) {
        CFArrayRef entries = (CFArrayRef)usage;
        CFIndex count = CFArrayGetCount(entries);
        for (CFIndex index = 0; index < count; index++) {
            CFTypeRef item = CFArrayGetValueAtIndex(entries, index);
            if (item && CFGetTypeID(item) == CFDictionaryGetTypeID()) {
                total = kb_gpu_saturating_add(
                    total, kb_cf_u64((CFDictionaryRef)item,
                                     CFSTR("accumulatedGPUTime")));
            }
        }
    } else if (type == CFDictionaryGetTypeID()) {
        total = kb_cf_u64((CFDictionaryRef)usage, CFSTR("accumulatedGPUTime"));
    }
    return total;
}

static int kb_gpu_accumulator_add(kb_gpu_accumulator *accumulator, int32_t pid,
                                  uint64_t nanoseconds)
{
    if (nanoseconds == 0) {
        return 0;
    }
    for (size_t index = 0; index < accumulator->count; index++) {
        if (accumulator->items[index].pid == pid) {
            accumulator->items[index].gpu_time_ns = kb_gpu_saturating_add(
                accumulator->items[index].gpu_time_ns, nanoseconds);
            return 0;
        }
    }
    if (accumulator->count == accumulator->capacity) {
        size_t capacity = accumulator->capacity == 0
            ? 32 : accumulator->capacity * 2;
        if (capacity < accumulator->capacity
            || capacity > SIZE_MAX / sizeof(kb_gpu_process)) {
            return -1;
        }
        kb_gpu_process *items = realloc(
            accumulator->items, capacity * sizeof(kb_gpu_process));
        if (!items) {
            return -1;
        }
        accumulator->items = items;
        accumulator->capacity = capacity;
    }
    accumulator->items[accumulator->count].pid = pid;
    accumulator->items[accumulator->count].gpu_time_ns = nanoseconds;
    accumulator->count++;
    return 0;
}

/* Returns 1 when the registry entry was already visited, 0 when it is new
   (and records it), -1 on allocation failure. */
static int kb_gpu_registry_id_seen(uint64_t **ids, size_t *count,
                                   size_t *capacity, uint64_t value)
{
    for (size_t index = 0; index < *count; index++) {
        if ((*ids)[index] == value) {
            return 1;
        }
    }
    if (*count == *capacity) {
        size_t next = *capacity == 0 ? 32 : *capacity * 2;
        if (next < *capacity || next > SIZE_MAX / sizeof(uint64_t)) {
            return -1;
        }
        uint64_t *grown = realloc(*ids, next * sizeof(uint64_t));
        if (!grown) {
            return -1;
        }
        *ids = grown;
        *capacity = next;
    }
    (*ids)[*count] = value;
    (*count)++;
    return 0;
}

int kb_gpu_process_list(kb_gpu_process **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;

    CFMutableDictionaryRef matching = IOServiceMatching("IOAccelerator");
    if (!matching) {
        return -1;
    }
    io_iterator_t accelerators = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching,
                                     &accelerators) != KERN_SUCCESS) {
        return -1;
    }

    kb_gpu_accumulator accumulator = {0};
    uint64_t *seen_ids = NULL;
    size_t seen_count = 0;
    size_t seen_capacity = 0;
    int saw_accelerator = 0;
    int saw_user_client = 0;
    int saw_app_usage = 0;
    int failed = 0;

    io_service_t accelerator = 0;
    while ((accelerator = IOIteratorNext(accelerators)) != 0) {
        saw_accelerator = 1;
        io_iterator_t children = 0;
        if (IORegistryEntryCreateIterator(accelerator, kIOServicePlane,
                                          kIORegistryIterateRecursively,
                                          &children) != KERN_SUCCESS) {
            failed = 1;
            IOObjectRelease(accelerator);
            break;
        }
        io_registry_entry_t child = 0;
        while ((child = IOIteratorNext(children)) != 0) {
            uint64_t entry_id = 0;
            if (IORegistryEntryGetRegistryEntryID(child, &entry_id) == KERN_SUCCESS) {
                int seen = kb_gpu_registry_id_seen(&seen_ids, &seen_count,
                                                   &seen_capacity, entry_id);
                if (seen < 0) {
                    failed = 1;
                    IOObjectRelease(child);
                    break;
                }
                if (seen) {
                    IOObjectRelease(child);
                    continue;
                }
            }

            CFTypeRef creator = IORegistryEntryCreateCFProperty(
                child, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0);
            CFTypeRef usage = IORegistryEntryCreateCFProperty(
                child, CFSTR("AppUsage"), kCFAllocatorDefault, 0);
            int32_t pid = kb_gpu_pid_from_creator(creator);
            if (pid > 0) {
                saw_user_client = 1;
            }
            if (usage) {
                saw_app_usage = 1;
            }
            if (pid > 0 && usage
                && kb_gpu_accumulator_add(&accumulator, pid,
                                          kb_gpu_app_usage_sum(usage)) != 0) {
                failed = 1;
            }
            if (creator) {
                CFRelease(creator);
            }
            if (usage) {
                CFRelease(usage);
            }
            IOObjectRelease(child);
            if (failed) {
                break;
            }
        }
        IOObjectRelease(children);
        IOObjectRelease(accelerator);
        if (failed) {
            break;
        }
    }
    IOObjectRelease(accelerators);
    free(seen_ids);

    if (failed || !saw_accelerator || (saw_user_client && !saw_app_usage)) {
        free(accumulator.items);
        return -1;
    }
    *out = accumulator.items;
    *count = accumulator.count;
    return 0;
}

void kb_gpu_process_list_free(kb_gpu_process *items)
{
    free(items);
}

static int kb_cf_int(CFDictionaryRef dictionary, CFStringRef key, int fallback)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return fallback;
    }
    int result = fallback;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &result)) {
        return fallback;
    }
    return result;
}

static int kb_cf_bool(CFDictionaryRef dictionary, CFStringRef key)
{
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (!value || CFGetTypeID(value) != CFBooleanGetTypeID()) {
        return 0;
    }
    return CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
}

int kb_power_stats_read(kb_power_stats *out)
{
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->charge_percent = -1;
    out->time_remaining_min = -1;

    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) {
        return -1;
    }
    CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
    if (!sources) {
        CFRelease(blob);
        return -1;
    }

    out->valid = 1;
    CFIndex count = CFArrayGetCount(sources);
    for (CFIndex index = 0; index < count; index++) {
        CFTypeRef source = CFArrayGetValueAtIndex(sources, index);
        CFDictionaryRef description = IOPSGetPowerSourceDescription(blob, source);
        if (!description) {
            continue;
        }
        CFStringRef type = CFDictionaryGetValue(description, CFSTR(kIOPSTypeKey));
        if (!type || CFGetTypeID(type) != CFStringGetTypeID() ||
            CFStringCompare(type, CFSTR(kIOPSInternalBatteryType), 0) != kCFCompareEqualTo) {
            continue;
        }

        out->has_battery = kb_cf_bool(description, CFSTR(kIOPSIsPresentKey));
        if (out->has_battery) {
            int current = kb_cf_int(description, CFSTR(kIOPSCurrentCapacityKey), -1);
            int maximum = kb_cf_int(description, CFSTR(kIOPSMaxCapacityKey), -1);
            if (current >= 0 && maximum > 0) {
                out->charge_percent = (int32_t)((int64_t)current * 100 / maximum);
            }
            out->is_charging = kb_cf_bool(description, CFSTR(kIOPSIsChargingKey));
            out->is_charged = kb_cf_bool(description, CFSTR(kIOPSIsChargedKey));

            CFStringRef state = CFDictionaryGetValue(description,
                                                     CFSTR(kIOPSPowerSourceStateKey));
            if (state && CFGetTypeID(state) == CFStringGetTypeID()) {
                out->is_plugged_in =
                    CFStringCompare(state, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo;
                CFStringGetCString(state, out->source, sizeof(out->source),
                                   kCFStringEncodingUTF8);
            }

            CFStringRef time_key = out->is_charging
                ? CFSTR(kIOPSTimeToFullChargeKey)
                : CFSTR(kIOPSTimeToEmptyKey);
            int minutes = kb_cf_int(description, time_key, -1);
            out->time_remaining_min = minutes > 0 ? minutes : -1;
        }
        break;
    }

    CFRelease(sources);
    CFRelease(blob);
    return 0;
}

int kb_disk_io_read(uint64_t *bytes_read, uint64_t *bytes_written,
                    uint64_t *read_ops, uint64_t *write_ops)
{
    if (!bytes_read || !bytes_written || !read_ops || !write_ops) {
        return -1;
    }
    *bytes_read = 0;
    *bytes_written = 0;
    *read_ops = 0;
    *write_ops = 0;

    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                     IOServiceMatching("IOBlockStorageDriver"),
                                     &iterator) != KERN_SUCCESS) {
        return -1;
    }

    int found = 0;
    io_service_t service = 0;
    while ((service = IOIteratorNext(iterator)) != 0) {
        CFMutableDictionaryRef properties = NULL;
        if (IORegistryEntryCreateCFProperties(service, &properties,
                                              kCFAllocatorDefault, 0) == KERN_SUCCESS
            && properties) {
            CFTypeRef statistics = CFDictionaryGetValue(
                properties, CFSTR(kIOBlockStorageDriverStatisticsKey));
            if (statistics && CFGetTypeID(statistics) == CFDictionaryGetTypeID()) {
                CFDictionaryRef dictionary = (CFDictionaryRef)statistics;
                *bytes_read += kb_cf_u64(
                    dictionary, CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey));
                *bytes_written += kb_cf_u64(
                    dictionary, CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey));
                *read_ops += kb_cf_u64(
                    dictionary, CFSTR(kIOBlockStorageDriverStatisticsReadsKey));
                *write_ops += kb_cf_u64(
                    dictionary, CFSTR(kIOBlockStorageDriverStatisticsWritesKey));
                found = 1;
            }
            CFRelease(properties);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return found ? 0 : -1;
}

int kb_prevent_sleep_pids(int32_t **pids, size_t *count)
{
    if (!pids || !count) {
        return -1;
    }
    *pids = NULL;
    *count = 0;

    CFDictionaryRef assertions = NULL;
    if (IOPMCopyAssertionsByProcess(&assertions) != kIOReturnSuccess ||
        !assertions) {
        return -1;
    }

    CFIndex total = CFDictionaryGetCount(assertions);
    size_t capacity = (size_t)(total > 0 ? total : 1);
    int32_t *result = (int32_t *)calloc(capacity, sizeof(int32_t));
    const void **keys = (const void **)calloc(capacity, sizeof(void *));
    const void **values = (const void **)calloc(capacity, sizeof(void *));
    if (!result || !keys || !values) {
        free(result);
        free(keys);
        free(values);
        CFRelease(assertions);
        return -1;
    }
    CFDictionaryGetKeysAndValues(assertions, keys, values);

    size_t found = 0;
    for (CFIndex index = 0; index < total; index++) {
        int32_t pid = 0;
        if (!keys[index] || CFGetTypeID(keys[index]) != CFNumberGetTypeID() ||
            !CFNumberGetValue((CFNumberRef)keys[index], kCFNumberSInt32Type, &pid)) {
            continue;
        }
        if (!values[index] || CFGetTypeID(values[index]) != CFArrayGetTypeID()) {
            continue;
        }
        CFArrayRef list = (CFArrayRef)values[index];
        CFIndex assertionCount = CFArrayGetCount(list);
        int prevents = 0;
        for (CFIndex item = 0; item < assertionCount && !prevents; item++) {
            CFTypeRef entry = CFArrayGetValueAtIndex(list, item);
            if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID()) {
                continue;
            }
            CFDictionaryRef dictionary = (CFDictionaryRef)entry;
            if (kb_cf_int(dictionary, kIOPMAssertionLevelKey, 0) <= 0) {
                continue;
            }
            CFStringRef type = CFDictionaryGetValue(dictionary,
                                                    kIOPMAssertionTypeKey);
            if (!type || CFGetTypeID(type) != CFStringGetTypeID()) {
                continue;
            }
            if (CFStringCompare(type,
                                kIOPMAssertionTypePreventUserIdleSystemSleep, 0)
                    == kCFCompareEqualTo ||
                CFStringCompare(type, kIOPMAssertionTypePreventSystemSleep, 0)
                    == kCFCompareEqualTo) {
                prevents = 1;
            }
        }
        if (prevents) {
            result[found++] = pid;
        }
    }

    free(keys);
    free(values);
    CFRelease(assertions);

    if (found == 0) {
        free(result);
        return 0;
    }
    *pids = result;
    *count = found;
    return 0;
}

int kb_host_stats_read(kb_host_stats *out)
{
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    mach_port_t host = mach_host_self();
    if (host == MACH_PORT_NULL) {
        return -1;
    }

    vm_size_t page_size = 0;
    if (host_page_size(host, &page_size) == KERN_SUCCESS && page_size > 0) {
        out->page_size = (uint64_t)page_size;
    } else {
        long fallback = sysconf(_SC_PAGESIZE);
        out->page_size = fallback > 0 ? (uint64_t)fallback : 4096;
    }

    size_t length = sizeof(out->mem_total);
    if (sysctlbyname("hw.memsize", &out->mem_total, &length, NULL, 0) != 0) {
        out->mem_total = 0;
    }

    struct xsw_usage swap;
    memset(&swap, 0, sizeof(swap));
    length = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &length, NULL, 0) == 0) {
        out->swap_total = swap.xsu_total;
        out->swap_used = swap.xsu_used;
        out->swap_avail = swap.xsu_avail;
        out->swap_encrypted = swap.xsu_encrypted ? 1 : 0;
    }

    /*
     * Memory pressure exactly as Activity Monitor reports it: the free
     * percentage from memorystatus_get_level, inverted, plus the kernel's
     * discrete pressure level (1 normal, 2 warning, 4 critical).
     */
    out->mem_pressure_percent = -1;
    out->mem_pressure_level = -1;
    int32_t pressure_percent = -1;
    int32_t pressure_level = -1;
    if (kb_memory_pressure_read(&pressure_percent, &pressure_level) == 0) {
        out->mem_pressure_percent = pressure_percent;
        out->mem_pressure_level = pressure_level;
    }

    struct timeval boot_time;
    memset(&boot_time, 0, sizeof(boot_time));
    length = sizeof(boot_time);
    int boot_mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(boot_mib, 2, &boot_time, &length, NULL, 0) == 0) {
        out->boot_time_us = ((uint64_t)boot_time.tv_sec * 1000000ULL) +
                            (uint64_t)boot_time.tv_usec;
    }

    double loads[3] = {0, 0, 0};
    if (getloadavg(loads, 3) == 3) {
        out->load_valid = 1;
        out->load1 = loads[0];
        out->load5 = loads[1];
        out->load15 = loads[2];
    }

    vm_statistics64_data_t vm;
    memset(&vm, 0, sizeof(vm));
    mach_msg_type_number_t vm_count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64,
                          (host_info64_t)&vm, &vm_count) == KERN_SUCCESS) {
        uint64_t page = out->page_size;
        out->mem_free = (uint64_t)vm.free_count * page;
        out->mem_active = (uint64_t)vm.active_count * page;
        out->mem_inactive = (uint64_t)vm.inactive_count * page;
        out->mem_wired = (uint64_t)vm.wire_count * page;
        out->mem_compressor = (uint64_t)vm.compressor_page_count * page;
        out->mem_speculative = (uint64_t)vm.speculative_count * page;
        out->mem_purgeable = (uint64_t)vm.purgeable_count * page;
        out->mem_internal = (uint64_t)vm.internal_page_count * page;
        out->mem_external = (uint64_t)vm.external_page_count * page;
    }

    natural_t cpu_count = 0;
    processor_info_array_t cpu_info = NULL;
    mach_msg_type_number_t cpu_info_count = 0;
    if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                            &cpu_count, &cpu_info, &cpu_info_count) == KERN_SUCCESS
        && cpu_info != NULL) {
        processor_cpu_load_info_t load =
            (processor_cpu_load_info_t)cpu_info;
        uint32_t count = cpu_count < KB_MAX_CORES ? (uint32_t)cpu_count : KB_MAX_CORES;
        out->core_count = count;
        for (uint32_t index = 0; index < count; index++) {
            out->cores[index].index = index;
            out->cores[index].user_ticks = load[index].cpu_ticks[CPU_STATE_USER];
            out->cores[index].system_ticks = load[index].cpu_ticks[CPU_STATE_SYSTEM];
            out->cores[index].idle_ticks = load[index].cpu_ticks[CPU_STATE_IDLE];
            out->cores[index].nice_ticks = load[index].cpu_ticks[CPU_STATE_NICE];
        }
        vm_deallocate(mach_task_self(), (vm_address_t)cpu_info,
                      (vm_size_t)cpu_info_count * sizeof(integer_t));
    }

    mach_port_deallocate(mach_task_self(), host);
    return 0;
}
