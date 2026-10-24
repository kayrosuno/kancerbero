#include "KBLaunchd.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <launch.h>
#pragma clang diagnostic pop

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char g_error[256];

const char *kb_launchd_last_error(void)
{
    return g_error;
}

static void kb_copy_string(launch_data_t value, char *buffer, size_t size)
{
    if (!value || !buffer || size == 0) {
        return;
    }
    if (launch_data_get_type(value) != LAUNCH_DATA_STRING) {
        return;
    }
    const char *text = launch_data_get_string(value);
    if (text) {
        snprintf(buffer, size, "%s", text);
    }
}

static void kb_copy_arguments(launch_data_t value, char *buffer, size_t size)
{
    if (!value || !buffer || size == 0) {
        return;
    }
    if (launch_data_get_type(value) != LAUNCH_DATA_ARRAY) {
        return;
    }
    size_t count = launch_data_array_get_count(value);
    size_t used = 0;
    buffer[0] = '\0';
    for (size_t i = 0; i < count && used + 2 < size; i++) {
        launch_data_t item = launch_data_array_get_index(value, i);
        if (!item || launch_data_get_type(item) != LAUNCH_DATA_STRING) {
            continue;
        }
        const char *text = launch_data_get_string(item);
        if (!text) {
            continue;
        }
        used += (size_t)snprintf(buffer + used, size - used, "%s%s",
                                 used ? " " : "", text);
    }
}

typedef struct {
    kb_launchd_job *items;
    size_t count;
    size_t capacity;
} kb_job_collector;

static int kb_grow(kb_job_collector *collector)
{
    if (collector->count < collector->capacity) {
        return 0;
    }
    size_t capacity = collector->capacity ? collector->capacity * 2 : 128;
    kb_launchd_job *items = (kb_launchd_job *)realloc(
        collector->items, capacity * sizeof(kb_launchd_job));
    if (!items) {
        return -1;
    }
    collector->items = items;
    collector->capacity = capacity;
    return 0;
}

static void kb_collect_job(const launch_data_t value, const char *key, void *context)
{
    kb_job_collector *collector = (kb_job_collector *)context;
    if (!value || launch_data_get_type(value) != LAUNCH_DATA_DICTIONARY) {
        return;
    }
    if (kb_grow(collector) != 0) {
        return;
    }

    kb_launchd_job *job = &collector->items[collector->count++];
    memset(job, 0, sizeof(*job));
    if (key) {
        snprintf(job->label, sizeof(job->label), "%s", key);
    }

    launch_data_t pid = launch_data_dict_lookup(value, LAUNCH_JOBKEY_PID);
    if (pid && launch_data_get_type(pid) == LAUNCH_DATA_INTEGER) {
        job->pid = (int32_t)launch_data_get_integer(pid);
    }

    launch_data_t status = launch_data_dict_lookup(value, LAUNCH_JOBKEY_LASTEXITSTATUS);
    if (status && launch_data_get_type(status) == LAUNCH_DATA_INTEGER) {
        job->last_exit_status = (int32_t)launch_data_get_integer(status);
    } else {
        job->last_exit_status = -1;
    }

    launch_data_t program = launch_data_dict_lookup(value, LAUNCH_JOBKEY_PROGRAM);
    if (program) {
        kb_copy_string(program, job->program, sizeof(job->program));
        job->has_program = job->program[0] != '\0';
    }
    launch_data_t arguments = launch_data_dict_lookup(value, LAUNCH_JOBKEY_PROGRAMARGUMENTS);
    if (arguments) {
        kb_copy_arguments(arguments, job->arguments, sizeof(job->arguments));
    }

    launch_data_t onDemand = launch_data_dict_lookup(value, LAUNCH_JOBKEY_ONDEMAND);
    if (onDemand && launch_data_get_type(onDemand) == LAUNCH_DATA_BOOL) {
        job->on_demand = launch_data_get_bool(onDemand) ? 1 : 0;
    }
}

int kb_launchd_jobs(kb_launchd_job **out, size_t *count)
{
    if (!out || !count) {
        return -1;
    }
    *out = NULL;
    *count = 0;
    g_error[0] = '\0';

    launch_data_t response = launch_msg(launch_data_new_string(LAUNCH_KEY_GETJOBS));
    if (!response) {
        snprintf(g_error, sizeof(g_error), "launch_msg(GetJobs) failed");
        return -1;
    }
    if (launch_data_get_type(response) != LAUNCH_DATA_DICTIONARY) {
        snprintf(g_error, sizeof(g_error), "unexpected launch_msg response type");
        launch_data_free(response);
        return -1;
    }

    kb_job_collector collector = {0};
    launch_data_dict_iterate(response, kb_collect_job, &collector);
    launch_data_free(response);

    *out = collector.items;
    *count = collector.count;
    return 0;
}

void kb_launchd_jobs_free(kb_launchd_job *jobs)
{
    free(jobs);
}
