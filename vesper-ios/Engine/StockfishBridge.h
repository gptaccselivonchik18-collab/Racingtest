#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

// The caller owns output, which must have room for at least six characters.
int vesper_best_move(const char *networkPath, const char *moves, int milliseconds,
                     char *output, size_t capacity);

#ifdef __cplusplus
}
#endif
