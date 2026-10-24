#ifndef KB_LAUNCHD_H
#define KB_LAUNCHD_H

#include "KBModels.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char label[KB_NAME_MAX];
    int32_t pid;
    int32_t last_exit_status;
    char program[KB_PATH_MAX];
    char arguments[2048];
    uint8_t on_demand;
    uint8_t has_program;
} kb_launchd_job;

int kb_launchd_jobs(kb_launchd_job **out, size_t *count);
void kb_launchd_jobs_free(kb_launchd_job *jobs);
const char *kb_launchd_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
