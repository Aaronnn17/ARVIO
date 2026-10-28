# Independent seek thumbnails

HTTP file previews can use a separate `:seek_preview` process with a persistent
software FFmpeg decoder. The worker reads through ARVIO's authenticated,
bounded loopback range proxy. It never seeks the main player, opens an audio
device, or reserves a hardware video decoder. Only small bitmaps and their
actual presentation timestamps cross Binder.

One low-priority extraction job uses at most two software slice threads to decode
an independent keyframe. Full-resolution deblocking is skipped for the 320px
thumbnail; the main playback decoder is unchanged. A
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

### Physical TV follow-up, 28 October 2026

The remote previously committed a seek after two seconds regardless of whether
its preview had finished. On the TCL ARMv7 TV a first native request took 3.36
seconds, so the UI could cancel a working decoder before displaying anything.
The commit timer now permits a bounded ten-second pending request and leaves a
newly delivered frame visible for at least 1.2 seconds. OK/Back remain immediate.

Background warming now requires eight seconds of buffered media (instead of 25)
and eight seconds of stable playback. The old threshold could exceed what the
80 MiB buffer holds for high-bitrate files. One frame may start every three
seconds; buffer, dropped-frame, foreground and memory protections remain active.
Only numeric preview timing/state diagnostics survive release log stripping.

Validation on the physical TCL Smart TV Pro, Android 14, normal signed release:

- 69 targeted JVM seek/preview tests passed, including pending-preview timeout
  and healthy-buffer regression coverage; release lint/build passed.
- Two 4K HDR episodes (6.29 GB and 7.60 GB) played with ahead warming enabled.
  Background frame requests succeeded during playback; playback resumed after
  quick seeking, and deliberately paused playback remained paused after scrubbing.
- Uncached foreground requests completed in 1,731, 1,505 and 1,338 ms. The cold
  worker's first background request completed in 3,357 ms including binding.
- A cached remote target displayed 60 ms after its input event. A physical-TV
  screenshot shows the selected frame and three cached neighbors together.
- The 7.60 GB stream subsequently produced ahead frames in 796–1,651 ms.
  These are measured examples, not a guarantee of instant uncached network reads
  or zero dropped frames on every source. Physical playback was observed, not
  instrumented with a baseline dropped-frame comparison.

### Faster five-frame strip

- The HTTP reader fetches 256 KiB chunks and reuses the final redirect request
  instead of resolving the download URL on every read. It retains the headers
  actually used on the final hop, and refreshes expired locations once through
  the original URL. Requests and signed URLs remain private.
- Memory lookups check neighboring cache buckets while still validating the
  real frame timestamp, source identity and generation. This prevents a valid
  frame from being missed solely because it was stored in an adjacent bucket.
- A neighbor request may queue after the foreground result has been delivered
  but before its worker cleanup finishes. It cannot preempt an active decode.
- Both forward slots are filled before the rewind slots. All five positions
  retain their geometry with subdued empty placeholders while loading, and a
  delivered center frame remains visible for at least two seconds before auto
  commit. If neighbors are still missing, auto commit allows up to four extra
  seconds for the paused window to finish. OK, Back and further seeking remain
  immediate; failed requests cannot leave browsing waiting indefinitely.
- Numeric native phase timings distinguish source opening, seeking, reads,
  decoding and scaling. They contain no source URL, headers or account details.
- 74 targeted JVM tests pass, including five-frame warming, the completion race,
  cross-bucket reuse, expired-link refresh and redirect-header preservation.
  All 20 native libraries retain 16 KiB ELF alignment across four ABIs.

Physical-TV measurements, 28 October 2026, TCL Smart TV Pro, Android 14:

- Normal signed release, 6.29 GB 4K HDR source: three fresh foreground requests
  took 868, 1,160 and 2,056 ms. Input-to-visible-center times were approximately
  977, 1,261 and 2,162 ms including debounce and UI delivery. These are examples,
  not a controlled before/after benchmark or a sub-500-ms guarantee.
- The slowest of those requests spent 1,455 ms reading source bytes, 347 ms
  decoding and 10 ms scaling. Smaller output alone cannot remove this latency.
- Cached target 874229 displayed 30 ms after input. Screenshots show two real
  frames on either side of the selected frame, with valid timestamps. Empty
  placeholders are not counted as successful thumbnails.
- The decoder uses at most two low-priority slice threads and skips full-size
  deblocking. Background warming remains conditional on healthy playback; no
  second hardware decoder is opened. A comparative dropped-frame baseline has
  not been measured, so these checks do not establish zero playback impact.
- Final installed release (APK SHA-256
  `d463f80964ef38baf70e8be1f2d01420c85a24d862d6796e98d4c15ef409d3e7`):
  a cold-worker request at 605461 ms took 2336 ms (2442 ms input to display).
  The four uncached neighbors completed in 759, 961, 1645 and 706 ms; the
  bounded timer committed only after the fourth finished, with `resume=false`.
  A repeat seek visibly showed all five actual frames. The full cold strip
  needed about 7.3 seconds from the final input, not half a second.
  Final release build/lint and all 74 targeted tests passed.
