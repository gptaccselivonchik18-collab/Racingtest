#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef bool (*coach_cancel_fn)(void *);
int coach_llama_generate(const char *path, const char *system, const char *prompt, char *output, int capacity, coach_cancel_fn cancelled, void *user);
#ifdef __cplusplus
}
#endif
