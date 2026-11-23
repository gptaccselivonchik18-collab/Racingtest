#include "StockfishBridge.h"

#include "attacks.h"
#include "engine.h"
#include "misc.h"
#include "position.h"
#include "tune.h"
#include "uci.h"

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace {
std::atomic<uint64_t> latest{0};
std::mutex handoff;
Stockfish::Engine *active = nullptr;
}

uint64_t vesper_replace_search() {
    std::lock_guard<std::mutex> guard(handoff);
    const auto revision = ++latest;
    if (active) active->stop();
    return revision;
}

int vesper_best_move_for(uint64_t revision, const char *networkPath, const char *moves,
                         int milliseconds, char *output, size_t capacity) {
    if (!networkPath || !moves || !output || capacity < 6 || milliseconds <= 0)
        return -1;
    output[0] = '\0';

    static std::mutex lock;
    std::lock_guard<std::mutex> guard(lock);
    if (revision != latest) return 0;
    static std::unique_ptr<Stockfish::Engine> engine;
    if (!engine) {
        const std::filesystem::path path(networkPath);
        std::error_code error;
        if (!std::filesystem::is_regular_file(path, error) || error)
            return -1;
        Stockfish::Attacks::init();
        Stockfish::Position::init();
        engine = std::make_unique<Stockfish::Engine>(path);
        Stockfish::Tune::init(engine->get_options());
        engine->set_on_verify_network([](std::string_view) {});
        engine->set_on_update_no_moves([](const Stockfish::Engine::InfoShort &) {});
        engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
        engine->set_on_iter([](const Stockfish::Engine::InfoIter &) {});
        engine->set_on_start([] {});
    }

    std::istringstream input(moves);
    std::vector<std::string> line;
    for (std::string move; input >> move;) line.push_back(move);
    if (engine->set_position(Stockfish::StartFEN, line))
        return -2;

    std::string best;
    engine->set_on_bestmove([&best](std::string_view move, std::string_view) { best = move; });
    Stockfish::Search::LimitsType limits;
    limits.movetime = milliseconds;
    limits.startTime = Stockfish::now();
    {
        std::lock_guard<std::mutex> guard(handoff);
        if (revision != latest) {
            engine->set_on_bestmove({});
            return 0;
        }
        engine->go(limits);
        active = engine.get();
    }
    engine->wait_for_search_finished();
    {
        std::lock_guard<std::mutex> guard(handoff);
        active = nullptr;
    }
    engine->set_on_bestmove({});
    if (revision != latest || best.size() < 4 || best.size() > 5)
        return 0;
    std::copy(best.begin(), best.end(), output);
    output[best.size()] = '\0';
    return 1;
}

int vesper_best_move(const char *networkPath, const char *moves, int milliseconds,
                     char *output, size_t capacity) {
    return vesper_best_move_for(vesper_replace_search(), networkPath, moves, milliseconds, output, capacity);
}
