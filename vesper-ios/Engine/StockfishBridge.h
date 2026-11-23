#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// The caller owns output, which must have room for at least six characters.
int vesper_best_move(const char *networkPath, const char *moves, int milliseconds,
                     char *output, size_t capacity);
uint64_t vesper_replace_search(void);
int vesper_best_move_for(uint64_t revision, const char *networkPath, const char *moves,
                         int milliseconds, char *output, size_t capacity);

#ifdef __cplusplus
}
#endif
