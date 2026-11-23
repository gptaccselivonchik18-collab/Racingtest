#include "StockfishBridge.h"

#include <cassert>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
    assert(argc == 2);
    char move[6]{};
    assert(vesper_best_move(argv[1], "", 100, move, sizeof(move)) == 1);
    std::cout << "White: " << move << '\n';
    assert(vesper_best_move(argv[1], "e2e4", 100, move, sizeof(move)) == 1);
    std::cout << "Black after e4: " << move << '\n';
    assert(vesper_best_move(argv[1], "e2e5", 100, move, sizeof(move)) == -2);
}
