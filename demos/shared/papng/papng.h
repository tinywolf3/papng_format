#pragma once
#include <stdint.h>
#if defined(_WIN32)
#if defined(PAPNG_BUILD)
#define PAPNG_API __declspec(dllexport)
#else
#define PAPNG_API __declspec(dllimport)
#endif
#else
#define PAPNG_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Handles are independent. Serialize calls for each handle; different handles may run on workers.
PAPNG_API void *pp_open(const unsigned char *bytes, int length);
PAPNG_API void pp_close(void *handle);
PAPNG_API const char *pp_error(void *handle);
PAPNG_API const char *pp_warnings(void *handle);
PAPNG_API const char *pp_metadata(void *handle);
// width, height, frames, masks, visible frame, ended, revision, sockets, clips, source kind (0 PNG/1 APNG/2
// PAPNG)
PAPNG_API int pp_get(void *handle, int field);
PAPNG_API const unsigned char *pp_pixels(void *handle);
PAPNG_API const unsigned char *pp_marks(void *handle);
PAPNG_API void pp_tick(void *handle, double seconds);
PAPNG_API void pp_step(void *handle);
PAPNG_API void pp_restart(void *handle, int clip);
PAPNG_API void pp_seek(void *handle, int frame);
PAPNG_API void pp_mask(void *handle, int index, double degrees);
PAPNG_API double pp_offset(void *handle, int index);
PAPNG_API void pp_select_mask(void *handle, int index);
// name kinds: 0 mask, 1 socket, 2 clip. Display labels may be shortened; pointers last until the next pp_name query.
PAPNG_API const char *pp_name(void *handle, int kind, int index);
PAPNG_API int pp_socket(void *handle, int index, double *xyz);
PAPNG_API int pp_hint(void *handle, int kind, double *values); // display, bbox, scale, pivot
PAPNG_API uint32_t pp_mean(void *handle, int mask);            // RGBA big-endian; alpha 0 means no samples
#ifdef __cplusplus
}
#endif
