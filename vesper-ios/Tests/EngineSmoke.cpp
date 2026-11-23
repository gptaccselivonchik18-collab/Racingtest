#include "StockfishBridge.h"

#include <cassert>
#include <chrono>
#include <future>
#include <iostream>
#include <string>
#include <thread>

int main(int argc, char **argv) {
    assert(argc == 2);
    char move[6]{};
    assert(vesper_best_move(argv[1], "", 100, move, sizeof(move)) == 1);
    std::cout << "White: " << move << '\n';
    assert(vesper_best_move(argv[1], "e2e4", 100, move, sizeof(move)) == 1);
    std::cout << "Black after e4: " << move << '\n';
    assert(vesper_best_move(argv[1], "e2e5", 100, move, sizeof(move)) == -2);

    const auto obsolete = vesper_replace_search();
    auto slow = std::async(std::launch::async, [&, obsolete] {
        char oldMove[6]{};
        return vesper_best_move_for(obsolete, argv[1], "", 4500, oldMove, sizeof(oldMove));
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(120));
    const auto current = vesper_replace_search();
    assert(slow.wait_for(std::chrono::seconds(2)) == std::future_status::ready);
    assert(slow.get() == 0);
    assert(vesper_best_move_for(obsolete, argv[1], "", 100, move, sizeof(move)) == 0);
    assert(vesper_best_move_for(current, argv[1], "e2e4", 100, move, sizeof(move)) == 1);
    std::cout << "Latest position replaced an in-flight search: " << move << '\n';
}
