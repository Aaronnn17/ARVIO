# Independent seek thumbnails

HTTP file previews can use a separate `:seek_preview` process with a persistent
software FFmpeg decoder. The worker reads through ARVIO's authenticated,
bounded loopback range proxy. It never seeks the main player, opens an audio
device, or reserves a hardware video decoder. Only small bitmaps and their
actual presentation timestamps cross Binder.

One low-priority decoding thread extracts independently decodable frames. A
frame farther than five seconds from the requested timestamp is rejected.
Cancellation interrupts network reads; source replacement invalidates cached
results. Existing preview byte budgets, timeouts, cache limits and playback
health checks still apply. Background work stops when playback is strained.

This supports H.264, HEVC and VP9 files up to 3840×2160, including unwatched
positions when the server supports byte ranges and the container has usable
seek information. HDR10/HLG output is tone-mapped for thumbnails. Dolby Vision
profile 5 lacks an HDR10-compatible base and is deliberately rejected. IPTV
sources retain their single-connection restriction. Provider images and
renderer captures remain available independently of this backend.

Cached previews are immediate; a cold frame still requires network reads and
decoding. This does not promise instant extraction at every timestamp or zero
CPU/network cost. The player always takes priority over speculative warming.

## Rebuilding the native libraries

Run `scripts/build-seek-keyframes.sh` on Linux/WSL with Android NDK r28c:

```sh
ANDROID_NDK_HOME=/path/to/android-ndk-r28c scripts/build-seek-keyframes.sh
```

The script verifies the official FFmpeg 8.0.1 source archive SHA-256 and builds
all four Android ABIs for API 23 with 16 KiB ELF alignment. `SEEK_ABIS`,
`SEEK_BUILD_DIR` and `SEEK_JOBS` can restrict/reuse builds. No FFmpeg source
patches are applied. The JNI bridge is `app/src/main/cpp/seek_keyframe.cpp`.

FFmpeg is dynamically linked, configured without GPL/nonfree components, and
distributed under LGPL 2.1 or later. The license is bundled in
`app/src/main/assets/licenses/ffmpeg-LGPL-2.1.txt`. Matching, unmodified source
is included in `third_party/ffmpeg/ffmpeg-8.0.1.tar.xz` (upstream:
https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz). The build script contains the
complete configuration and allows rebuilding/replacing the shared libraries.
No code from the AGPL mpvRx project is included.

## Validation

`KeyframeWorkerDeviceTest` checks authenticated ranges, unwatched 4K Main10
frames, actual timestamps, cancellation, source replacement, memory-pressure
recovery and cache hits.
`SeekPreviewStreamingDeviceTest` accepts an optional private on-device fixture
with `nativeKeyframes: true`; it checks remote unwatched positions without
logging URLs or headers. Private fixtures must never be committed.

The live playback comparison requires actual rendered video, successful preview
generation during playback, and successful resume after seeking. Its optional
`previewUrl` lets an emulator play a supported file while extracting thumbnails
from a heavier file. Reports explicitly identify that arrangement; it is a
resource-contention test, not proof of full-resolution playback support on that
emulator or every physical TV. A simulated HEVC decoder failure must not be
counted as a successful audio-only playback benchmark.

### Emulator checks, 27 October 2026

- 97 preview JVM tests passed.
- API 34 phone and API 31 TV workers decoded unwatched synthetic 4K Main10
  frames with correct timestamps and colors. The TV test also verified
  cancellation, source replacement and recovery after a memory-pressure callback.
- A cached 28.2 GB debrid remux produced validated frames at 2, 10, 20 and 30
  minutes without prior playback. Optimized phone timings were 2,477 ms for
  the first request and 882/880/790 ms for the later uncached positions.
- On the 2 GB TV emulator, a supported 720p stream rendered while the worker
  extracted five ahead frames from that 4K remux. Baseline (30 seconds) and
  preview work (45 seconds) each had zero rebuffers and dropped frames. Five
  paused-browsing thumbnails loaded; cached lookup p95 was 0.059 ms; resume
  after seek succeeded with zero player errors.
- Full 4K playback was not validated: the emulator's platform HEVC decoders
  rejected it. An earlier 1080p contention run had one rebuffer in both windows
  and failed the strict zero-rebuffer assertion; it is not counted as a pass.
  These results do not guarantee zero impact on every physical device/network.
