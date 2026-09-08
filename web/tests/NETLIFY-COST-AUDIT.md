# Netlify Cost Audit

Audit date: 2026-09-08. Workspace: `C:/Users/arvin/ARVIO-WEB-PLAYBACK`.
This audit used local source, mocked tests, and bounded read-only Netlify API requests with existing CLI authentication. No deployment, billing changes, credential rotation, account changes, or auth-backend edits were performed.

## Conclusions

- Concrete web relay gaps were closed: the subtitle route previously bypassed the metadata proxy's DNS/size policy, and mislabeled binary responses could pass through the generic proxy.
- No arbitrary media/playlist relay was found in the auth backend's source, redirects, or deployed function inventory. This does not attribute its observed bandwidth to another endpoint.
- A repeated full-account transfer path exists in playback progress saving. It is actionable, but its share of production bandwidth has not been measured.
- The current backend does not support a progress-patch write protocol. Client-only sparse writes are unsafe. `cloud.ts` remains unchanged.
- No daily/monthly extrapolations, billed-credit estimates, or measured savings are claimed below.

## Actual Account Measurement

Read-only source: `GET https://api.netlify.com/api/v1/accounts/{account}/bandwidth`, HTTP 200 during this audit.

| Field returned by API | Value |
| --- | --- |
| `used` | 6,912,131,183 bytes |
| `last_updated_at` | `2026-09-08T14:44:27.659+00:00` |
| `period_start_date` | `2026-09-07T00:00:00.000-07:00` |
| `period_end_date` | `2026-10-07T00:00:00.000-07:00` |

The explicit accounting window is September 7 at 07:00 UTC through October 7 at 07:00 UTC. The usage value is a partial-period counter at the reported update time, not a daily total or a complete month's usage. No subsequent account counter or actual billed-credit total was verified for this report.

### Domain Ranking Coverage

Read-only source: `GET https://api.netlify.com/api/v1/accounts/{account}/bandwidth/ranking`, HTTP 200, fetched alongside the account counter. Selected returned entries:

| Host | Returned byte count |
| --- | ---: |
| `auth.arvio.tv` | 5,719,818,696 |
| `arvio.tv` | 770,075,196 |
| `web.arvio.tv` | 272,760,176 |
| `arvio-web.netlify.app` | 122,828,653 |

The ranking response did not supply its own start/end timestamps or update watermark. Its exact coverage was therefore not independently established. These selected entries are not a complete reconciliation of the account counter. In particular, **5.72 GB on auth must not be described as 5.72 GB/day or treated as a verified endpoint-specific measurement**.

## Actual Function Log Samples

Read-only source: `https://analytics.services.netlify.com/v2/sites/{auth-site-id}/function_logs/{function}`, using bounded historical GET requests. These successful samples requested the preceding hour. The spans below are the first and last returned report timestamps, not the full query coverage.

| Function | Returned log entries | Distinct requests with report entries | Observed report span, UTC on 2026-09-08 |
| --- | ---: | ---: | --- |
| `account-sync-pull` | 100 | 100 | 13:51:55.879 - 13:53:51.282 |
| `tmdb-proxy` | 100 | 100 | 14:04:18.033 - 14:04:22.458 |
| `app-usage-event` | 100 | 40 | 13:51:58.267 - 14:00:32.613 |
| `tv-auth-status` | 100 | 100 | 13:52:58.214 - 14:37:07.271 |

Responses repeatedly stopped at 100 entries without an exposed pagination cursor. Treat these as incomplete samples and lower bounds on observed requests, not hourly totals, per-installation polling rates, or proof that one client caused a loop. The `app-usage-event` sample included 60 ordinary log lines in addition to 40 report entries; counting all 100 as invocations would be wrong.

An earlier `account-sync-cursor` query for `2026-09-08T13:48:28.500Z` through `2026-09-08T14:48:28.500Z` returned zero log entries. That is not a billing measurement or proof of zero requests through all routes/caches.

A later attempt to narrow pull/push/usage/cursor samples to `13:52:00Z` through `13:52:30Z` returned HTTP 401 at approximately `15:24:56Z`. No new counts were obtained from those failures; empty parsed results must not be reported as zero traffic. The management environment API subsequently succeeded, so the log-access failure is not evidence that all Netlify read access was unavailable.

Response sizes, cache-hit counts, client/account attribution, exact request totals, compute charges, and billed credits were not verified. The samples cannot explain the domain ranking's bytes by themselves.

## Production Configuration Checks

- `ALLOW_NETLIFY_MEDIA_PROXY` and `NEXT_PUBLIC_ALLOW_NETLIFY_MEDIA_PROXY` were absent from the auth/web site environment API, shared account environment API, and legacy `build_settings.env` checks. No production values were changed.
- The web site's production `NEXT_PUBLIC_ARVIO_RESOLVER_URL` was subsequently verified with HTTP 200 as `https://resolve.arvio.tv/`. This is a public base URL, with no credentials or query parameters.
- The deployed auth function inventory matched its authentication, sync, tracker/metadata, entitlement, and maintenance functions; no generic video relay function appeared.
- Auth redirects resolve account-deletion pages, not external media targets. Auth tracker proxies construct URLs on fixed TMDB/Trakt/Simkl API hosts.
- Live TV logos use provider `stream_icon` / `tvg-logo` values directly in image elements. Home-server artwork URLs are also direct. No ordinary logo path through the web metadata proxy was identified.

## Actionable Auth Cost Findings

### 1. Progress Checkpoints Transfer Whole Account Documents

At inspection, `PlayerOverlay` throttled ordinary signed-in, non-live progress saves to 15 seconds and forced saves on pause, background/pagehide, cleanup, and end. The actual call chain is:

1. `saveProgress()` updates one profile's continue-watching item.
2. `mutateCloudPayload()` explicitly invalidates the five-second raw-payload cache and reads a fresh full account snapshot.
3. `writeRawPayload()` posts the full modified account document to `account-sync-push`.
4. The backend stores full account-ID and email-keyed snapshots and appends a full snapshot event.

Thus the small logical checkpoint can require a full-document download and upload plus backend storage work. This is a code-proven cost amplification path, not proof of the measured auth bandwidth's cause. No payload sizes or per-viewer production rates were measured.

Source locations at inspection: [PlayerOverlay.tsx](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/components/player/PlayerOverlay.tsx:1199), [saveProgress](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/lib/cloud.ts:1437), [mutation queue](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/lib/cloud.ts:715), and [snapshot storage](C:/Users/arvin/ARVIO-WEB-PLAYBACK/netlify-auth-site/netlify/functions/_backend.js:1969).

Ordinary checkpoints now run every 60 seconds instead of 15 seconds. Tests verify that pause, background, pagehide, cleanup and end still flush immediately and unchanged positions are not saved twice. This reduces scheduled checkpoints by 75%; it is not a measured reduction of total hosting cost, and full-document persistence remains a backend limitation.

### 2. No Existing Delta-Write Protocol Can Be Reused

`settingsOutbox` stores pending local changes and retries `saveCloudSettings()`. That function still calls full-document `mutateCloudPayload()`; local field-difference logic is not a server patch protocol.

The current `account-sync-push` requires `body.payload` and returns HTTP 400 with `reason: "missing_payload"` without it. Accepted writes replace the snapshot payload after specific addon, tracking, and token guards. There is no general sparse merge, progress operation, expected revision, stable mutation-ID acknowledgement, or progress-tombstone contract. `account-sync-delta` returns an empty event list and a wall-clock cursor; it is not a write API.

Sending a sparse object as `payload` could be rejected as a poorer snapshot or lose unrelated state. Removing the fresh read would also change concurrency semantics. No such client shortcut was made, and `cloud.ts` was left unchanged.

A future progress-delta protocol needs separate backend review: authenticated profile ownership, exact title/episode identity, atomic conflict handling, original event ordering, removal/completion tombstones, and idempotent retries. It must retain pause/close/end durability. No new endpoint or backend deployment is part of this audit.

Sources: [settingsOutbox.ts](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/lib/settingsOutbox.ts:28), [saveCloudSettings](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/lib/cloud.ts:856), [account-sync-push.js](C:/Users/arvin/ARVIO-WEB-PLAYBACK/netlify-auth-site/netlify/functions/account-sync-push.js:120), [account-sync-delta.js](C:/Users/arvin/ARVIO-WEB-PLAYBACK/netlify-auth-site/netlify/functions/account-sync-delta.js:8).

### 3. Other Polling Evidence Is Not Enough to Change Auth Behavior

- Web account reads already share in-flight requests and have a five-second per-account cache. The settings outbox's 30-second retry timer exits immediately when no settings are pending. It is not an unconditional auth heartbeat.
- Focus/visibility refreshes are visibility-gated and debounced, and refresh work is single-flight. The observed aggregate snapshot burst does not identify one of these triggers as faulty.
- The TMDB report burst warrants a read-only review of cache hits, repeated path/query combinations, language/page variants, and callers. Distinct cold requests are not equivalent to repeated cache misses for one resource.
- TV/Discord pairing advertises a three-second interval and a ten-minute expiry. No production evidence established that one client continued polling after completion/expiry. Intervals and auth semantics were not changed.
- `app-usage-event` reports small acknowledgements while writing usage state. Its sample does not support attributing the auth bandwidth ranking to heartbeat responses.

Next attribution step, subject to access: inspect auth response bytes by route and cache status in existing Netlify observability, over an explicit bounded time window. Do not add paid telemetry or collect raw account payloads/credentials to infer costs.

## Implemented Web Safeguards

| Changed file | Safeguard |
| --- | --- |
| [safeProxy.ts](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/lib/server/safeProxy.ts) | Hosted/production media opt-in disabled independently of public flags; media paths checked on every redirect; range/partial responses and binary media rejected; caller cancellation reaches upstream and releases the dispatcher. |
| [proxy route](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/app/api/proxy/route.ts) | Default playlist rewriting does not route segments back through Netlify; channel catalogs retain full-query CDN caching; live HLS is excluded from the hour-long catalog cache, including `.m3u`/`get.php` cases. |
| [subtitle route](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/app/api/subtitle/route.ts) | DNS-pinned metadata fetch, request budget, 2 MiB bound, cancellation, uncached errors, and full-query subtitle cache variation. |
| [netlify.toml](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/netlify.toml) | Both media-proxy build flags explicitly false. |
| [netlify-cost.test.cjs](C:/Users/arvin/ARVIO-WEB-PLAYBACK/web/tests/netlify-cost.test.cjs) | Focused mocked-provider, cancellation, binary/mislabel, bounded-image/SVG, subtitle, and playlist-cache regressions. |

Images are bounded to 4 MiB and 16,777,216 pixels and verified with the metadata reader from Next's existing optional Sharp dependency. Original image bytes/formats are preserved; there is no image re-encoding. SVG receives the same byte limit, `nosniff`, and sandboxed CSP. Missing image-decoder support fails closed.

## Remaining Limits

- Image metadata verification is not content sanitization; trailing data can remain inside the 4 MiB response. Range/partial-response rejection prevents turning the route into a ranged image-disguised media reader. No absolute guarantee against arbitrary data encoded inside valid metadata is claimed.
- The existing 128 MiB limit remains for large text metadata/catalogs. Known `.m3u8` fetches and subtitles use 2 MiB budgets. Extensionless/misnamed HLS is also rejected above 2 MiB before being returned, but may be identified only after reading under the broader metadata budget.
- Request budgets are per warm function instance, not an account-wide quota or spending ceiling. Rejected requests can still consume invocations; CDN hits can still incur request/bandwidth charges.
- Metadata, catalogs, auth, static assets, and small manifests still use hosting resources. The safeguards do not make the application cost-free.
- No production savings, billing total, or rollout result was verified. Production behavior changes only after a separately authorized deployment.

## Verification Snapshot

Commands run from `C:/Users/arvin/ARVIO-WEB-PLAYBACK/web`:

```text
node --test --test-reporter=spec tests/*.test.cjs
407 passed, 0 failed, 0 skipped, 0 TODOs

node node_modules/typescript/bin/tsc --noEmit --incremental false
Passed (exit 0)
```

The shared suite includes 30 focused Netlify cost tests and three progress-checkpoint tests. The production web build and dependency audit also passed. No billing mutation or production savings measurement was used for this audit.
