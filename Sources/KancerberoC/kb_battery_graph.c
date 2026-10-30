#include "KancerberoC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* Activity Monitor reads its Energy-tab battery graph from a private C
   function in libsystemstats (in the dyld shared cache). It returns a
   dictionary with charge samples and AC/battery transitions for the last
   12 hours; times are seconds before the call. Activity Monitor serializes
   the call on a private queue, so it is never invoked concurrently. */

typedef CFDictionaryRef (*kb_battery_graph_fn)(void);

static kb_battery_graph_fn g_function;
static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static void kb_battery_graph_load_once(void)
{
    void *handle = dlopen("/usr/lib/libsystemstats.dylib", RTLD_NOW | RTLD_LOCAL);
    if (handle) {
        g_function = (kb_battery_graph_fn)dlsym(handle,
                                                "systemstats_get_battery_charge_graph");
    }
    if (!g_function) {
        g_function = (kb_battery_graph_fn)dlsym(RTLD_DEFAULT,
                                                "systemstats_get_battery_charge_graph");
    }
}

static CFArrayRef kb_array(CFDictionaryRef dict, const char *key)
{
    CFStringRef name = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    if (!name) {
        return NULL;
    }
    CFArrayRef array = (CFArrayRef)CFDictionaryGetValue(dict, name);
    CFRelease(name);
    if (!array || CFGetTypeID(array) != CFArrayGetTypeID()) {
        return NULL;
    }
    return array;
}

static int kb_copy_doubles(CFArrayRef array, double **out, size_t *count)
{
    CFIndex n = array ? CFArrayGetCount(array) : 0;
    *out = NULL;
    *count = 0;
    if (n <= 0) {
        return 1;
    }
    double *values = malloc((size_t)n * sizeof(double));
    if (!values) {
        return 0;
    }
    for (CFIndex i = 0; i < n; i++) {
        CFTypeRef item = CFArrayGetValueAtIndex(array, i);
        double value = 0;
        if (item && CFGetTypeID(item) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)item, kCFNumberDoubleType, &value);
        }
        values[i] = value;
    }
    *out = values;
    *count = (size_t)n;
    return 1;
}

/* The system reports 0 while on AC power and 1 while on battery. */
static int kb_copy_states(CFArrayRef array, int32_t **out, size_t *count)
{
    CFIndex n = array ? CFArrayGetCount(array) : 0;
    *out = NULL;
    *count = 0;
    if (n <= 0) {
        return 1;
    }
    int32_t *values = malloc((size_t)n * sizeof(int32_t));
    if (!values) {
        return 0;
    }
    for (CFIndex i = 0; i < n; i++) {
        CFTypeRef item = CFArrayGetValueAtIndex(array, i);
        int on_ac = 0;
        if (item && CFGetTypeID(item) == CFBooleanGetTypeID()) {
            on_ac = CFBooleanGetValue((CFBooleanRef)item) ? 0 : 1;
        } else if (item && CFGetTypeID(item) == CFNumberGetTypeID()) {
            int state = 0;
            CFNumberGetValue((CFNumberRef)item, kCFNumberIntType, &state);
            on_ac = state == 0;
        }
        values[i] = on_ac;
    }
    *out = values;
    *count = (size_t)n;
    return 1;
}

int kb_battery_charge_graph_read(kb_battery_charge_graph *out)
{
    if (!out) {
        return 0;
    }
    memset(out, 0, sizeof(*out));
    pthread_once(&g_once, kb_battery_graph_load_once);
    if (!g_function) {
        return 0;
    }

    /* "get" naming: the returned dictionary is not owned by the caller. */
    pthread_mutex_lock(&g_lock);
    CFDictionaryRef dict = g_function();
    if (!dict || CFGetTypeID(dict) != CFDictionaryGetTypeID()) {
        pthread_mutex_unlock(&g_lock);
        return 0;
    }

    CFArrayRef chargeTimes = kb_array(dict, "charge_times");
    CFArrayRef chargeLevels = kb_array(dict, "charge_levels");
    if (!chargeTimes || !chargeLevels) {
        pthread_mutex_unlock(&g_lock);
        return 0;
    }

    size_t timesCount = 0;
    size_t levelsCount = 0;
    int ok = kb_copy_doubles(chargeTimes, &out->charge_times, &timesCount) &&
             kb_copy_doubles(chargeLevels, &out->charge_levels, &levelsCount);
    if (!ok) {
        pthread_mutex_unlock(&g_lock);
        kb_battery_charge_graph_free(out);
        return 0;
    }
    /* Use the common prefix when the two arrays disagree. */
    out->charge_count = timesCount < levelsCount ? timesCount : levelsCount;

    CFArrayRef stateTimes = kb_array(dict, "battery_times");
    CFArrayRef states = kb_array(dict, "battery_states");
    size_t stateCount = 0;
    if (!kb_copy_doubles(stateTimes, &out->state_times, &stateCount)) {
        pthread_mutex_unlock(&g_lock);
        kb_battery_charge_graph_free(out);
        return 0;
    }
    out->state_count = stateCount;
    if (states) {
        size_t statesCount = 0;
        if (!kb_copy_states(states, &out->on_ac, &statesCount)) {
            pthread_mutex_unlock(&g_lock);
            kb_battery_charge_graph_free(out);
            return 0;
        }
        if (statesCount != stateCount) {
            /* Activity Monitor logs "chargeDict malformed" and draws no bands. */
            free(out->on_ac);
            free(out->state_times);
            out->on_ac = NULL;
            out->state_times = NULL;
            out->state_count = 0;
        }
    }
    pthread_mutex_unlock(&g_lock);
    return out->charge_count > 0 ? 1 : 0;
}

void kb_battery_charge_graph_free(kb_battery_charge_graph *graph)
{
    if (!graph) {
        return;
    }
    free(graph->charge_times);
    free(graph->charge_levels);
    free(graph->state_times);
    free(graph->on_ac);
    memset(graph, 0, sizeof(*graph));
}
