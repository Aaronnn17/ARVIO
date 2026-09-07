# Matlock physical-TV verification, 2026-09-07

## Setup

- TCL Smart TV Pro G08, existing Arvind profile and configured sources.
- Installed 1.9.996 (312), built from `808468854`, over 1.9.996 (311).
- Verified the installed and replacement APK share the release certificate.
- In-place update only: no uninstall or data clear; all three profiles remained.
- Matlock S1E10, "Crash Helmets On", duration 42:35. The preview codec reported
  1920x1080 AVC. The selected addon name was not independently recorded.

## Results

| Check | Observation | Result |
| --- | --- | --- |
| Quick timeline, 04:02 | A real scene different from paused playback appeared | Functional pass; cold delay |
| Commit 04:02 | Main playback subsequently showed the scene in the preview | Visual scene-match pass |
| Main timeline, 06:02 | A different real scene appeared after a deadline/retry | Functional pass; latency fail |
| Backward main timeline, 03:22 | Repeated deadlines and no initial frame; eventually a real earlier scene appeared | Recovery/latency fail |
| Existing account data | Arvind, Shai., Leyla remained available | Pass |

The successful screenshots are not evidence of instant cold extraction. Exact input-to-display
latency was not instrumented. The 03:22 image was only confirmed on a much later screenshot,
not within a usable interactive deadline. No universal-preview or release-readiness pass.

Warnings captured from the physical device:

```text
11:58:54.492 targetMs=362448 elapsedMs=6004 status=UNAVAILABLE reason=deadline
12:00:46.598 targetMs=202448 elapsedMs=6004 status=UNAVAILABLE reason=deadline
12:00:57.681 targetMs=202448 elapsedMs=6014 status=UNAVAILABLE reason=deadline
12:01:33.763 targetMs=202448 elapsedMs=6005 status=UNAVAILABLE reason=deadline
```

## Local screenshot evidence

- `C:/Users/arvin/arvio-matlock-quick-waited.png`: quick preview at 04:02.
- `C:/Users/arvin/arvio-matlock-committed.png`: matching scene after commit.
- `C:/Users/arvin/arvio-matlock-main-forward.png`: main preview at 06:02.
- `C:/Users/arvin/arvio-matlock-main-backward.png`: initial backward failure.
- `C:/Users/arvin/arvio-matlock-current.png`: eventual backward frame at 03:22.

## Follow-up investigation

The provider waits for an unfinished `inFlight` future before submitting another decode.
Media3 1.9.0 serializes extraction and resource release through a shared execution sequencer;
`FrameExtractor.close()` queues release rather than interrupting active extraction. Therefore
clearing the local future alone would not safely reset the underlying decoder. Do not apply
that apparent fix without covering cancellation and actual decoder recovery.

Investigate bounded decoder lifecycle/reuse and recovery, with a physical cold/backward-seek
regression test. Raising deadlines alone has not met interactive performance requirements.

## Additional automated coverage

`PlayerSeekPreviewVisualDeviceTest` exercises the production PlayerScreen with a three-scene
local clip: TV quick forward/backward and phone touch forward/backward. One test passed on
each emulator (TV 11.046 seconds; phone 13.433 seconds). The test checks scene colors distinct
from the paused main video. These fixture results do not supersede the physical-TV failures.
