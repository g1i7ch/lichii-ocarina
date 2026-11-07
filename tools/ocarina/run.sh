#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
    printf 'Usage: %s /path/to/game.nup\n' "$0" >&2
    exit 2
fi

game_path=$(realpath -- "$1")
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
build_dir=$(realpath -- "${LICHII_BUILD_DIR:-$repo_root/build}")

if [[ ! -x "$build_dir/bin/lichii" ]]; then
    printf 'Build Lichii first. Expected executable at %s/bin/lichii\n' "$build_dir" >&2
    exit 1
fi

export EDEN_NX2_SPLIT=1
export EDEN_NX2_FRAMES_AHEAD=0
export EDEN_NX2_PRELOAD_ALL_PIPELINES=1

cd -- "$build_dir/bin"
exec ./lichii "$game_path"
