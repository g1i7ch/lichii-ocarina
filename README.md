# Lichii Ocarina

A fork of [Lichii build 93](https://github.com/zortos293/Lichii/releases/tag/build-93) focused on getting Ocarina of Time running better on PC.

It fixes slow-motion movement below 60 FPS, reduces speed bursts after shader stalls, and includes fixes for rendering corruption. Testing was done on Linux with an Intel Core i9-13900K and NVIDIA RTX 3090 Ti.

## Start here

Read the [detailed Ocarina guide](docs/OCARINA_GUIDE.md) for prerequisites, build commands, configuration, source provenance, validation, save handling, and troubleshooting.

```bash
git clone https://github.com/g1i7ch/lichii-ocarina.git
cd lichii-ocarina

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DYUZU_TESTS=ON -DBUILD_TESTING=ON \
  -DYUZU_ROOM=OFF \
  -DENABLE_WEB_SERVICE=OFF \
  -DENABLE_UPDATE_CHECKER=OFF \
  -DENABLE_QT_TRANSLATION=OFF

cmake --build build --parallel 8
./build/bin/tests '[nx2_oot_time],[patch_manager],[buffer_ports]'
./tools/ocarina/run.sh /path/to/your/game.nup
```

Install the dependencies in the guide before configuring. The helper accepts a local game path and uses the existing emulator configuration. Select **Normal** CPU clock, **High** GPU accuracy, and enable **Real-time speed (built-in)** in the game's Add-Ons. The guide describes the performance tradeoffs.

## Changes in this fork

- Port Lichii PR #216's measured-frame-time approach into build 93's guarded patch format.
- Exclude stalls longer than 100 ms from the timing average, reducing post-stall acceleration.
- Port Lichii PR #185's deferred-clear ordering fix for image blits, DMA writes, and copies.
- Invalidate deleted GPU-buffer references across active channels, including inactive bindings.
- Add timing, patch-conflict, and cross-channel buffer-deletion regression coverage.
- Provide a Linux launch helper that disables frame-ahead overlap and preloads cached pipelines.

## Current results and limits

On the test system, movement felt more consistent and rendering errors became less frequent. Shader-compilation hitches and FPS drops still happen. We saw roughly 20–40 FPS across different scenes and settings, so treat those numbers as a rough idea of performance.

The tested regression groups pass **282 assertions across 20 test cases**. The full test suite and other hardware platforms have not been validated for this fork. Native Linux was tested. Windows and macOS builds remain untested.

The source release requires locally supplied game and system data. Build outputs, personal profiles, game dumps, saves, keys, firmware, shader caches, and machine-specific desktop launchers are excluded from this repository.

## Credits and licensing

Lichii inherits work from Eglantine, Eden, yuzu, Sudachi, and their contributors. Timing work originates with gunvalk's PR #216. Deferred-clear ordering originates with WeslieDE's PR #185. Cross-channel buffer invalidation was adapted from A-Man-With-A-Plan-dev's Ocarina fork. See the guide for pinned source references and the scope of each adaptation.

The source retains its existing GPL and third-party license notices. See [LICENSE.txt](LICENSE.txt), [LICENSES](LICENSES), and the preserved [upstream README](README.upstream.md).
