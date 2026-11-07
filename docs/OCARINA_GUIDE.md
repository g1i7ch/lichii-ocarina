# Ocarina timing, rendering, and build guide

## Scope and baseline

This fork targets the Ocarina of Time Switch 2 application identified by title ID `0400486024DEC000`. The built-in game patches are restricted to the `main` module with build ID `E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348`.

The source baseline is Lichii build 93, commit `09b78bd2dfdd279cc81caed2a794ed85062725c9`. Pinning the baseline makes the changes and test results reproducible. Upstream development may subsequently change these behaviors.

Game packages can carry misleading filenames or differing display-version metadata. The title ID, module name, original instruction bytes, and module build ID determine whether the timing patch applies.

## What was investigated

The original symptoms included slow movement and camera rotation below 60 FPS, bursts of accelerated movement after stalls, black or corrupted scenes, green video output in earlier builds, and intermittent freezes while entering new areas.

The controller reached full stick deflection. Moving the same game between builds and disabling timing patches changed movement speed, which supported investigating emulated timing separately from controller calibration.

The final source changes address timing and GPU resource lifetime or ordering. Earlier green-video and startup failures were encountered in other builds and are not established as universally fixed by this patch set.

## Prerequisites

The validated build environment was CachyOS on x86-64 Linux with GCC, CMake, Ninja, Qt 6, SDL 3, FFmpeg, and the NVIDIA Vulkan driver. The test machine had an Intel Core i9-13900K, 64 GiB RAM, and an RTX 3090 Ti with 24 GiB VRAM.

Upstream requires CMake 3.31 or newer. Dependency versions are defined in `cpmfile.json` and the upstream CMake files. Initial configuration downloads dependencies, so it needs network access and free disk space. Limit build parallelism when RAM is constrained.

On an Arch-derived system, the following covers the common system dependencies used by the source build. Package availability follows the distribution's repositories.

```bash
sudo pacman -S --needed \
  base-devel git cmake ninja pkgconf \
  qt6-base qt6-charts qt6-tools \
  sdl3 ffmpeg libusb opus openssl \
  libzip lz4 zlib zstd \
  vulkan-icd-loader
```

The GPU also needs its working Vulkan driver. Verify it with `vulkaninfo --summary` if the Vulkan tools package is installed. The baseline's CMake dependency manager can obtain several additional libraries automatically.

Qt Charts is required by the GUI. A configure error mentioning `Qt6ChartsConfig.cmake` means its development package is missing or CMake cannot find it. Install a Qt Charts package compatible with the installed Qt version.

For other platforms, begin with the [upstream build documentation](Build.md). The changes retain the upstream C++ implementation, but this fork's runtime results are from Linux only.

## Build

```bash
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DYUZU_TESTS=ON \
  -DBUILD_TESTING=ON \
  -DYUZU_ROOM=OFF \
  -DENABLE_WEB_SERVICE=OFF \
  -DENABLE_UPDATE_CHECKER=OFF \
  -DENABLE_QT_TRANSLATION=OFF

cmake --build build --parallel 8
```

The GUI executable is `build/bin/lichii`. The CMake target retains the upstream name `yuzu`. The command-line frontend is `build/bin/eden-cli`.

The build produces local executables. This repository does not publish prebuilt release packages. Keep the source checkout with its build output so rebuilding and reviewing changes remain straightforward.

## Validate

Run the regression groups exercised during development.

```bash
./build/bin/tests '[nx2_oot_time],[patch_manager],[buffer_ports]'
```

The final targeted run consists of 282 assertions across 20 test cases.

| Group | Coverage | Recorded result |
| --- | --- | --- |
| `nx2_oot_time` and `patch_manager` | Timing at several frame rates, long stalls, patch guards, disabling, user-mod precedence, and conflicting timing add-ons | 97 assertions in 9 cases passed |
| `buffer_ports` | Existing buffer-cache regressions plus inactive-channel deletion and slot reuse | 185 assertions in 11 cases passed |

The new cross-channel deletion case contributes 32 assertions. It creates two active GPU channels sharing a buffer, deletes the buffer while one channel is current, reuses its slot, and checks invalidation and dirty flags in the other channel. It also checks that unrelated bindings survive.

The full suite was not run for this fork. A successful compile and targeted tests do not establish visual correctness in every scene. Deferred-clear ordering was ported from an existing upstream change; its scene-level effect requires gameplay checks.

## Launch

```bash
./tools/ocarina/run.sh /path/to/your/game.nup
```

The helper resolves the local game path, changes into the build's executable directory, and starts Lichii. Set `LICHII_BUILD_DIR` to use a different build directory.

```bash
LICHII_BUILD_DIR=/path/to/another/build \
  ./tools/ocarina/run.sh /path/to/your/game.nup
```

The helper uses these environment settings.

| Setting | Value | Purpose and tradeoff |
| --- | --- | --- |
| `EDEN_NX2_SPLIT` | `1` | Uses the secondary GPU execution thread while keeping macros on that thread. It was more compatible than split mode 2 in the tests here. |
| `EDEN_NX2_FRAMES_AHEAD` | `0` | Waits for the current frame before returning its buffers to the game. This can cost throughput, but reduces overlapping reads and writes. |
| `EDEN_NX2_PRELOAD_ALL_PIPELINES` | `1` | Builds all compatible cached graphics pipelines during startup. This trades longer startup and additional driver memory for fewer cached-pipeline builds during play. |

These are the helper's defaults, not global desktop settings. Launch `build/bin/lichii` directly for the upstream environment behavior. The helper does not select a display server, compositor, monitor mode, HDR mode, frame generator, or desktop icon.

## Emulator configuration

Start with the following settings, then change one variable at a time while comparing the same scene.

| Setting | Starting value | Reason |
| --- | --- | --- |
| Graphics API | Vulkan | Used throughout the Linux runtime tests |
| Resolution scale | 1× | Limits extra rendering load during compatibility testing |
| GPU accuracy | High | The user reported substantially cleaner rendering in this mode |
| CPU clock | Normal | Keeps guest counter behavior comparable across timing tests |
| Speed limit | Enabled, 100% | Avoids intentional turbo or slow modes |
| Frame pacing | Auto | The timing patch already adjusts the game step to measured presentation intervals |
| Disk shader cache | Enabled | Preserves translated shader and pipeline information |
| Vulkan driver pipeline cache | Enabled | Preserves compatible driver pipeline compilation data |
| Asynchronous shader compilation | Disabled initially | Matches the cleaner-rendering baseline; native draw-discard experiments can omit rendering work |
| Asynchronous presentation | Disabled initially | Matches the tested baseline |

In the game's Properties and Add-Ons, enable **Real-time speed (built-in)**. Disable **Dynamic FPS by Dark (built-in)** while testing this fork so the intended timing choice is explicit.

The code also handles both entries being enabled. The real-time hook is applied first, and the shared original-byte check prevents the older routine from applying over it. A regression test covers this interaction.

**Max Resolution (built-in)** is independent. The later bootable validation kept it enabled. Disabling it permits the game's dynamic-resolution path and may reduce rendering load, but that combination was not validated as the final baseline.

GPU accuracy Low improved throughput in some trials but coincided with visual problems. High mode can reduce FPS because stricter synchronization also affects available parallelism. Movement timing and visual correctness should be checked alongside the FPS counter.

## Timing implementation

The supported game module computes a frame step from its target rate. At lower actual frame rates, that fixed step produced slow movement.

The real-time patch replaces the original instruction at `main+0x6E6CC4` with a branch to executable padding. A short routine loads a floating-point delta from `main+0x3C461E0`, then returns to the original continuation.

Each presentation updates that delta using `std::chrono::steady_clock`. The correction converges to approximately 1.0 at 60 FPS, 2.0 at 30 FPS, and 3.0 at 20 FPS. Smoothing limits abrupt changes, and the delta is bounded from 1.0 to 4.0.

This fork differs from the initial PR by excluding samples longer than 100 ms from the average. The previous averaged value is retained for such a sample, and the timestamp advances. A large shader stall therefore does not become an instruction to accelerate the next several frames.

At 32 FPS, the timing test converges to 1.875. A subsequent one-second stall leaves that value unchanged, and ordinary frames continue from the same timing baseline.

The patch validates the title, module, build ID, original hook bytes, executable padding, buffer bounds, and user modifications before applying its records. The presentation path writes a delta only when the relocated hook was detected in the loaded process.

The four-times delta cap limits correction at very low frame rates. Some game systems may also use fixed time steps outside the patched location. Normal movement in the tested scenes does not establish correct timing everywhere.

## Rendering fixes

### Deferred depth clears

Lichii PR #185 adds deferred-clear flushes before successful image blits, write-enabled DMA image preparation, and image copies. A deferred occlusion-depth clear could otherwise land after a scene-depth copy and overwrite it. The documented Ocarina symptom was a terrain layer drawing over the scene.

This port preserves the three upstream ordering changes and existing renderer interfaces. Separate fog, exposure, video, and driver issues can still exist.

### Deleted buffer references across channels

The original deletion path invalidated bindings in the current GPU channel. Other channels could retain the deleted buffer ID. Reusing that slot for an unrelated buffer could then make those bindings resolve to the wrong resource.

The adapted deletion path visits active channels, clears matching index, vertex, uniform, storage, transform-feedback, and compute bindings, and marks the corresponding state dirty. It preserves unrelated bindings and the existing multirange invalidation logic. The regression exercises deletion followed by actual slot reuse.

## Saves, configuration, and caches

Back up the emulator's NAND and configuration directories before migrating between builds. The NAND contains user profiles and save data needed to preserve the same in-game identity.

Lichii retains upstream Eden/Eglantine directory naming. The exact selected directories depend on the version and configuration. Check `NANDDir`, `SaveDir`, `ConfigDir`, and `CacheDir` in the log, or open the user folder from the emulator's File menu.

On Linux, the inherited portable mode checks for a directory named `user` in the current working directory. The launch helper runs from the executable directory, so an intentional `build/bin/user` directory selects that portable profile.

When copying a configuration, inspect absolute NAND, SD card, load, dump, TAS, and save-directory settings. They can continue pointing at an older profile even when XDG paths or portable folders change. Reset those entries or set them to the intended new paths before assuming that profiles are isolated.

Exit normally after playing. Pipeline data and the recent-used-pipeline list are saved during operation and shutdown. Force-stopping a process can interrupt those writes. Keep game packages and profile data outside the source checkout's tracked files.

## Stutter mitigation and remaining limits

Logs from the tested setup recorded individual shader or pipeline stalls around 0.5 seconds and, in one ten-second interval, about 1.12 seconds of draws held for unbuilt pipelines. Other 600-frame intervals had no frames above 100 ms. This supports shader work as one cause of intermittent hitches rather than proving every FPS drop has that cause.

Preloading moves work for known compatible pipelines to startup. New effects and areas can still introduce new pipelines during play. A large accumulated cache also consumes more driver memory. If startup or memory usage becomes excessive, launch directly or remove the preload-all setting from your own launch configuration.

Keep one cache while testing the same build and driver. Revisit the same route when comparing behavior. A previously visited area and a new area are different workloads.

The experimental native asynchronous draw-discard switch can skip writes needed by later effects. It is intentionally absent from the helper. Enabling it may trade visible rendering work for fewer compilation waits.

The original machine often operated around 20–40 FPS depending on scene and settings. Sustained 60 FPS, universal artifact removal, and stutter-free traversal have not been established. Building software in the background also added CPU load during some development trials; compare performance after compilation finishes.

## Source provenance

| Component | Source | Adaptation in this fork |
| --- | --- | --- |
| Base emulator | [Lichii build 93](https://github.com/zortos293/Lichii/releases/tag/build-93), commit `09b78bd2dfdd279cc81caed2a794ed85062725c9` | Baseline source and existing licenses retained |
| Measured frame-time correction | [gunvalk's Lichii PR #216](https://github.com/zortos293/Lichii/pull/216), commit `6b9dda058ab274512ad3502c2f055bb4b8936251` | Ported into build 93's byte-record patch format, with existing bounds and padding guards |
| Post-stall timing behavior | Local change in `nx2_oot_time.h` | Samples over 100 ms are excluded, with added 32 FPS regression coverage |
| Deferred-clear ordering | [WeslieDE's Lichii PR #185](https://github.com/zortos293/Lichii/pull/185), merge `f99fb8ab7b604f60d3b25cae3a8c39f1ae258c09` | Three existing upstream flush points ported |
| Cross-channel buffer invalidation | [A-Man-With-A-Plan-dev's Ocarina stable fork](https://github.com/A-Man-With-A-Plan-dev/Eglantine/releases/tag/oot-stable-2026-11-05), fix `43b6b17c3a` | Adapted to build 93's channel structure, retaining multirange invalidation and omitting fields absent from this baseline |

The older Dark timing routine remains upstream code and retains its original credit. It is available for comparison through Add-Ons, subject to the shared-hook protection above.

## Reporting a regression

Include the repository commit, OS, GPU driver, game module build ID, relevant settings, reproduction route, whether the cache was warm, and the filtered test result. Compare the same save and camera position when reporting FPS.

Inspect logs for personal paths before sharing them. Share a minimal log excerpt and the relevant timings. Keep game packages, keys, firmware, saves, memory dumps, and full frame-resource captures local.

Useful log messages include `Applying built-in patch`, `Skipping`, `last 600 presents`, and `Runtime pipelines`. The first pair verifies patch selection. The latter pair separates average presentation intervals, long frames, fence waits, and compilation stalls.

## License

The inherited emulator source and local changes follow the existing GPL-3.0-or-later licensing where specified. Individual upstream files retain their own notices. Third-party components keep their respective licenses in `LICENSES` and their source directories. See `LICENSE.txt` and `README.upstream.md`.
