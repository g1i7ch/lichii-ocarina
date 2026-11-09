# Ocarina of Time on Linux: what limited the frame rate, and what fixed it

Findings from one machine (i9-13900K, RTX 3090 Ti, NVIDIA 620.70.06, CachyOS, Hyprland, game in
gamescope), moving from Lichii build 93 plus a timing/rendering patch set to build-125. Measured with
the emulator's own `last 600 presents` log line (printed every ~20 s).

| | build 93 + patches | build-125, first run (single GPU thread, FIFO) |
| --- | --- | --- |
| average frame | 33-42 ms | 18.6 ms over 28 samples (53.8 fps), 16.7 ms in places |
| blocked on the GPU fence | 17-24 ms | 0 ms |
| mesh topology errors | 52 | 0 |
| draws skipped | yes | 0 |

## Things outside the emulator

1. **Feral GameMode 1.8 pins games to the "fastest" cores.** `pin_cores` is on by default and its
   autodetection only handles a few CPUs; on a 13900K it picked the favored 5.8 GHz cores (CPUs 8-11,
   two physical cores) and re-applied the mask every 5 s. Lichii registers with GameMode when its
   GameMode setting is on, so all 86 threads ran on 4 logical CPUs. Check with
   `grep Cpus_allowed_list /proc/<pid>/status`. Fix: `~/.config/gamemode.ini` with `park_cores=no`
   and `pin_cores=no` under `[cpu]`. Frame times dropped from 33-42 ms to 18-24 ms on the spot.
2. **FIFO vsync inside gamescope** at a 120 Hz nested refresh snaps the present rate to 120/n: 60, 40,
   30. Mailbox lets the game's own 60 Hz vsync event pace it; gamescope composites, so no tearing.
3. **`EDEN_NX2_FRAMES_AHEAD=0`** serialises the game and the GPU thread. Upstream measured Ocarina at
   30.9 fps with 0 against 38.9 with the per-title default (1).

## Settings

- **GPU accuracy Fast.** The GPU thread split (front/back threads, pinned to their own cores) only
  runs in this mode and with DMA accuracy not Safe. With High there is no `GPUBack` thread and no
  "GPU thread split" line in the log.
- The ini marks each key with `key\default=true`; while that flag is set the value line is ignored.
  `tools/ocarina/tweak-config.py` clears the flag when it edits a key. The emulator rewrites the ini
  on exit, so edit it while the emulator is not running (the launcher does this once at start).
- Worth trying one at a time: *Ocarina of Time anti-aliasing: No sharpening* (~6 % faster, softer
  image), async shaders with *Switch 2 draws with unbuilt pipelines: Bounded*, the Frame rate limit
  slider once 60 holds (FPS Unlock keeps game logic at real time).

## Rendering issues seen on build 93 and their status

- **Bush leaves vanish up close, invisible objects you collide with**: build 93 rejected mesh
  shaders with point topology (`Mesh output topology 0 ... is not implemented`) and skipped those
  draws. Upstream accepts topologies 0 and 1 since build ~117; issue #596 shows the same class of
  missing walls/doors when mesh draws are skipped.
- **Blinding white bloom columns and streaks**: issues #867, #483, #788. Bad (NaN) values in one
  buffer reach the bloom pass; cause still open, a NaN-guard build is being tested. Restarting clears
  it. Issue #101's workaround (`LICHII_NO_BLOOM=1` in `tools/ocarina/run.sh`) rejects the bloom
  upsample programs at the cost of bloom accumulation and the river surface.
- Boot-time `Uncached storage pointer classification` errors come from preloading old-cache
  pipelines (`EDEN_NX2_PRELOAD_ALL_PIPELINES=1`); they rebuild during play with no skipped draws.

## This branch

`build-125-ocarina` = upstream tag `build-125` (cbb512ee) + the cross-channel buffer invalidation
from the build-93 patch set (the other two changes of that set are upstream now: #185 merged, the
real-time timing patch superseded by FPS Unlock #655). Build as upstream describes; run with
`tools/ocarina/run.sh /path/to/game.nup` (`LICHII_GAMESCOPE=1` for gamescope).
