#!/usr/bin/env bash
# Launch Ocarina of Time (0400486024DEC000) on a Linux build of Lichii.
#
#   tools/ocarina/run.sh /path/to/game.nup
#
# Environment:
#   LICHII_BUILD_DIR     build directory (default: <repo>/build)
#   LICHII_GAMESCOPE=1   wrap in gamescope (args from LICHII_GAMESCOPE_ARGS; defaults below)
#   LICHII_SPLIT         override EDEN_NX2_SPLIT (upstream default 2; 1 was more compatible on build 93)
#   LICHII_FRAMES_AHEAD  override EDEN_NX2_FRAMES_AHEAD (unset = per-title default, 1 for Ocarina;
#                        0 serialises game and GPU: 30.9 vs 38.9 fps in upstream's measurement)
#   LICHII_PRELOAD=0     don't build every cached pipeline at boot
#   LICHII_NO_BLOOM=1    issue #101 workaround for the blinding white bloom: rejects the bloom
#                        upsample programs and one overlay (no bloom accumulation, no river surface)
#
# On first launch the script sets vsync to Mailbox and GPU accuracy to Fast in the portable
# profile (build/bin/user/config/qt-config.ini), once; see tweak-config.py for why.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
BUILD="${LICHII_BUILD_DIR:-$ROOT/build}"
GAME="${1:?usage: $0 /path/to/game.nup}"
GAME="$(realpath -- "$GAME")"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
[ -n "${LICHII_SPLIT:-}" ] && export EDEN_NX2_SPLIT="$LICHII_SPLIT"
[ -n "${LICHII_FRAMES_AHEAD:-}" ] && export EDEN_NX2_FRAMES_AHEAD="$LICHII_FRAMES_AHEAD"
export EDEN_NX2_PRELOAD_ALL_PIPELINES="${LICHII_PRELOAD:-1}"
unset EDEN_NX2_TENSOR EDEN_NX2_PRESENT_QUEUE
if [ "${LICHII_NO_BLOOM:-0}" = "1" ]; then
    export EDEN_NX2_REJECT_HASH=f2b14c43ca0e4300,96dd01c5b0361fcb,c72b6ea746c00433
fi

CONFIG_DIR="$BUILD/bin/user/config"
if [ -f "$CONFIG_DIR/qt-config.ini" ] && [ ! -f "$CONFIG_DIR/.tweaks-applied" ]; then
    python3 "$ROOT/tools/ocarina/tweak-config.py" --vsync-mailbox --gpu-fast "$CONFIG_DIR/qt-config.ini" \
        && touch "$CONFIG_DIR/.tweaks-applied"
fi

cd -- "$BUILD/bin"
if [ "${LICHII_GAMESCOPE:-0}" = "1" ]; then
    # shellcheck disable=SC2086
    exec gamescope ${LICHII_GAMESCOPE_ARGS:---backend wayland --fullscreen --force-windows-fullscreen} \
        -- env ENABLE_GAMESCOPE_WSI=1 ./lichii "$GAME"
fi
exec ./lichii "$GAME"
