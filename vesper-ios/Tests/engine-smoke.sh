#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stockfish="$PWD/Vendor/stockfish/src"
out="$PWD/.build/engine-test"
mkdir -p "$out"
export stockfish out
mapfile -t sources < <(find "$stockfish" -name '*.cpp' ! -name main.cpp ! -name glue.cpp ! -name p_hm.cpp ! -path '*/universal/*' ! -path '*/emscripten/*' | sort)
printf '%s\n' "${sources[@]}" | xargs -P 3 -d '\n' -I '{}' bash -c 'g++ -std=c++17 -O2 -pthread -DIS_64BIT -DNNUE_EMBEDDING_OFF -I"$stockfish" -c "$1" -o "$out/$(basename "$1").o"' _ '{}'
g++ -std=c++17 -O2 -pthread -DIS_64BIT -DNNUE_EMBEDDING_OFF -IEngine -I"$stockfish" Tests/EngineSmoke.cpp Engine/StockfishBridge.cpp "$out"/*.o -o "$out/smoke"
"$out/smoke" "$PWD/Vendor/resources/nn-1a298aa575a0.nnue"
