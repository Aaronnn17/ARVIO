# Browser playback verification

## Automated checks

From `web`, run `npm ci`, `npm test`, `npx tsc --noEmit --incremental false`, and
`npm run build`. The tests cover playback routing, M3U request headers, home-server
negotiation/session ownership, transport recovery and teardown, remux cancellation,
rapid seeks, bounded buffering, and long-GOP fragment backpressure.

Home-server tests use API fixtures, not customer servers. They include exact Plex
version/part selection, Jellyfin/Emby PlaybackInfo profiles, original-account session
credentials, failed-start retries, stale results, StrictMode and source changes.

## Interactive reproduction

1. Install FFmpeg with libx264, AAC, E-AC-3 and DTS encoding support.
2. Run `powershell -File tests/create-playback-fixtures.ps1` from `web`.
3. Install `netlify-auth-site` dependencies with `npm ci` in that directory. The
   fixture server uses its existing esbuild package; alternatively set `ESBUILD_PATH`
   to an installed esbuild module's absolute path.
4. From `web`, run `node tests/playback-ui-server.cjs`, then open
   `http://127.0.0.1:3099`. Select each source, seek forward/back, switch audio,
   pause/resume and close. The page displays decoded dimensions, frame count,
   playhead, audio RMS, buffered ranges and errors.
5. For the actual ARVIO overlay, start the normal dev server with
   `ARVIO_UI_FIXTURES=true`, open `/dev/stabilization` and use the MKV/HLS test
   buttons. This route is disabled outside development.

Generated media stays in the ignored `.playback-fixtures` directory, outside
`public`. It contains only generated test patterns and tones, not hosted movies.

## Results recorded on 2026-09-08

- Chromium browser, 960x540 synthetic fixtures: E-AC-3 video/audio conversion played
  with nonzero audio RMS; measured probe 140 ms, first frame 714 ms in one run.
- DTS conversion: probe 376 ms, first frame 1,582 ms; at 31 seconds, 749 decoded
  video frames, readyState 4, audio RMS 0.0625 and no error.
- Silent MKV: probe 164 ms, first frame 361 ms; at 73.7 seconds, 1,772 decoded
  frames and no error. Absence of audio is valid, not a playback failure.
- Actual ARVIO overlay: MKV playback, +30/-30 seeking, English-to-Dutch audio
  selection with position retained, pause, close and switch to HLS passed.
- HLS quality selection and diagnostics worked in the overlay. The settings panel
  was visually checked at a 390x844 mobile viewport.
- Transport fixture: actual HLS playback/seek/reload/pause, DASH playback/quality/
  seek/reload, and MPEG-TS VOD playback/teardown passed. Adaptive audio switching
  and return-to-live behavior also have API-mock coverage, but were not tested
  against a real multitrack live provider.
- A development hot-reload run was interrupted; the clean overlay run was repeated
  without edits during playback. No production-duration soak was performed.

These are local fixture timings, not Internet startup guarantees. Real Plex,
Jellyfin and Emby accounts, Safari/iOS hardware, provider outages and large remote
remuxes still need provider/device acceptance tests. Do not describe fixtures as
proof that every server or codec works.

## Operational limits

No video relay/transcoder was added to Netlify. File repackaging and supported
audio conversion run in a browser worker. Unsupported video codecs require an
authorized home-server/provider conversion route or an external player. Browser
HTTPS, CORS, byte-range and codec restrictions still apply. The existing optional
media relay is not a promise of free or unlimited bandwidth. No automatic probing
of every source or background torrent download was added.
