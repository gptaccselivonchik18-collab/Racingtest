#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p Vendor/stockfish Vendor/resources
cache="${VESPER_CACHE_DIR:-$PWD/.build/downloads}"
mkdir -p "$cache"
fetch() {
    local file="$cache/$1"
    if ! printf '%s  %s\n' "$3" "$file" | shasum -a 256 -c >/dev/null 2>&1; then
        curl -fL --retry 3 "$2" -o "$file.tmp"
        printf '%s  %s\n' "$3" "$file.tmp" | shasum -a 256 -c
        mv "$file.tmp" "$file"
    fi
}
fetch stockfish.tgz https://codeload.github.com/nmrugg/stockfish.js/tar.gz/refs/tags/v19.0.1 a18aa8a871f5265014b110b3e07804ff3637899d2e189be6ded2b99e2c17a10e
fetch chess.tgz https://registry.npmjs.org/chess.js/-/chess.js-1.4.0.tgz dce92e280439d7a16f645be94f22e6da50e579a1f3011d0a2381755bfe2c2ef7
fetch nn-1a298aa575a0.nnue https://media.githubusercontent.com/media/official-stockfish/networks/master/nn-1a298aa575a0.nnue 1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2
tar -xzf "$cache/stockfish.tgz" -C Vendor/stockfish --strip-components=1
tar -xOzf "$cache/chess.tgz" package/dist/cjs/chess.js > Vendor/resources/chess-rules.js
tar -xOzf "$cache/chess.tgz" package/LICENSE > Vendor/resources/ChessJS-LICENSE.txt
cp "$cache/nn-1a298aa575a0.nnue" Vendor/resources/
cp Vendor/stockfish/Copying.txt Vendor/resources/Stockfish-GPL.txt
cp Vendor/stockfish/AUTHORS Vendor/resources/Stockfish-AUTHORS.txt

# The same prebuilt board shipped by the pinned Pages revision.
web_revision=a6e1dea135e60794c3b60019dddbc3040b4b9661
mkdir -p Vendor/Web
repo="$(git rev-parse --show-toplevel)"
git -C "$repo" fetch --no-tags --depth=1 https://github.com/gptaccselivonchik18-collab/Racingtest.git "$web_revision"
git -C "$repo" archive "$web_revision" chess | tar -x -C Vendor/Web
test -f Vendor/Web/chess/index.html
