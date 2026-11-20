#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$(realpath -m "${1:?Pass an output directory}")"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

fetch() {
    curl --fail --silent --show-error --location --retry 3 "$1" -o "$work_dir/$2"
    printf '%s  %s\n' "$3" "$work_dir/$2" | sha256sum -c
}

fetch https://registry.npmjs.org/stockfish/-/stockfish-19.0.1.tgz stockfish.tgz c3695e2a3afbc61c6439c689cb8b95cec4627bcda407193f6b7c3a5702fac839
fetch https://registry.npmjs.org/chess.js/-/chess.js-1.4.0.tgz chess.tgz dce92e280439d7a16f645be94f22e6da50e579a1f3011d0a2381755bfe2c2ef7
fetch https://static.crates.io/crates/chasolver/chasolver-3.0.0.crate chasolver.crate 4763d18e44aaef7e4968b7aa7c62556ce69d9b91b82d785187e11cd287b5bf16
fetch https://media.githubusercontent.com/media/official-stockfish/networks/master/nn-1a298aa575a0.nnue full.nnue 1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2

mkdir -p "$work_dir/stockfish" "$work_dir/chess" "$work_dir/.vesper" "$work_dir/downloads/cha"
tar -xzf "$work_dir/stockfish.tgz" --strip-components=1 -C "$work_dir/stockfish"
tar -xzf "$work_dir/chess.tgz" --strip-components=1 -C "$work_dir/chess"
tar -xzf "$work_dir/chasolver.crate" --strip-components=1 -C "$work_dir/downloads/cha"
cp -r "$source_dir/adjudicator" "$work_dir/.vesper/"
rustup toolchain install 1.93.1 --profile minimal --target wasm32-unknown-unknown
cargo +1.93.1 build --locked --manifest-path "$work_dir/.vesper/adjudicator/Cargo.toml" --target wasm32-unknown-unknown --release
python3 "$source_dir/build.py" "$work_dir/stockfish/bin" "$work_dir/full.nnue" \
    "$work_dir/chess/dist/cjs/chess.js" \
    "$work_dir/.vesper/adjudicator/target/wasm32-unknown-unknown/release/vesper_rules.wasm" "$output_dir"
