#include "../Native/CoachLlama.h"
#include <cstdio>
#include <cstring>
bool never(void *) { return false; }
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char output[24000] = {};
    int n = coach_llama_generate(argv[1], "Отвечай кратко по-русски.", "Напиши одним словом: как называется столица Франции?", output, sizeof(output), never, nullptr);
    printf("LOCAL_MODEL_RESULT code=%d text=%s\n", n, output);
    // This verifies real model execution and UTF-8 Cyrillic output, not MLBB expertise.
    bool cyrillic = false;
    for (int i=0; i+1<n; ++i) if ((unsigned char)output[i] == 0xD0 || (unsigned char)output[i] == 0xD1) cyrillic = true;
    return n > 0 && cyrillic ? 0 : 2;
}
