#include "KancerberoC.h"

/*
 * Version strings are injected by Config/Version.xcconfig through
 * GCC_PREPROCESSOR_DEFINITIONS. They are compile-time constants on purpose: a
 * daemon that is still running from an older bundle must report the version it
 * was built with, not the version of the app bundle that replaced it on disk.
 */
#ifndef KANCERBERO_VERSION
#define KANCERBERO_VERSION "0.0.0"
#endif

#ifndef KANCERBERO_BUILD_VERSION
#define KANCERBERO_BUILD_VERSION "0"
#endif

const char *kb_version(void)
{
    return KANCERBERO_VERSION;
}

const char *kb_build_version(void)
{
    return KANCERBERO_BUILD_VERSION;
}
