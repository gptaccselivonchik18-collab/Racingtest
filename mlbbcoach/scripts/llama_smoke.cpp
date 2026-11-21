#include "../Native/CoachLlama.h"
#include <cstdio>
bool never(void *) { return false; }
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char output[24000] = {};
    int n = coach_llama_generate(argv[1], "You are a helpful assistant. Always answer in Russian using Cyrillic characters. Use one short sentence.", "Объясни, зачем нужно отступать при низком здоровье.", output, sizeof(output), never, nullptr);
    printf("BEGIN_RUSSIAN\n%s\nEND_RUSSIAN\n", output);
    if (n <= 0) return 2;
    n = coach_llama_generate(argv[1], "You analyze observed MLBB state. Return only valid JSON. No Markdown. Do not infer enemy positions or hidden data.", "Observed state: ownHealth=0.2; positions, gold, cooldowns and patch unknown. Compare exactly two actions: gatherInformation and recover. Return JSON {selected: one action, confidence: integer 0-100, alternatives: [{action: one action, reason: insufficientEvidence or healthLimited, utility: integer 0-100, risk: integer 0-100}, ...]}. Use double quotes for all keys and strings.", output, sizeof(output), never, nullptr);
    printf("BEGIN_DECISION\n%s\nEND_DECISION\n", output);
    return n > 0 ? 0 : 3;
}
