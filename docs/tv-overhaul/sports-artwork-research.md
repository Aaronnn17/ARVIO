# Sports event artwork: implementation decision

Research checked on 2026-09-10. This is a proposal, not a claim that a new provider
is enabled. No third-party code, API keys or artwork was copied into this PR.

## Why the current cards repeat

ARVIO currently uses programme artwork from the playlist, then conservatively
matches artwork from installed sports addons. When neither provides a match,
it displays a bundled sport photograph. The last cached-provider audit found no
safe matches among the 20 addon artwork entries. A different stock photograph
does not solve missing event identity or coverage.

## Useful existing projects

- [Jellyfin.Plugin.TheSportsDB](https://github.com/retrorat1/Jellyfin.Plugin.TheSportsDB)
  is MIT-licensed. Its episode provider resolves sports events and fetches the
  matched event's thumbnail and fanart. It handles team pairs and non-team events.
  This is a useful reference for an ARVIO metadata adapter, not an Android plugin
  we can load directly.
- [Kodi's TheSportsDB scraper](https://www.thesportsdb.com/docs_kodi_scraper)
  is another metadata reference, particularly for motorsport and UFC. It targets
  sports recordings rather than live IPTV guide matching; it is not a complete
  live-schedule solution.
- The sports-centre reference implementation reviewed for this overhaul uses a
  backend fixture endpoint and team/league badges. It does not provide a reusable
  public banner feed. Do not call another application's private backend or reuse
  its credentials.

## Recommended artwork order

1. Verified artwork for the exact event, preferring a landscape thumbnail/fanart.
2. A locally rendered matchup card with both verified, unmodified team crests,
   names and competition identity. Use a neutral background, not a guessed venue.
3. Verified competition/session artwork for non-team events, including the actual
   race, qualifying session or fight card when identified.
4. The existing honest sport fallback when metadata remains ambiguous.

[TheSportsDB artwork documentation](https://www.thesportsdb.com/docs_artwork)
lists 1280x720 event thumbnails/fanart and transparent team/league logo assets.
Not every event has every asset. Do not promise official, 4K, or universal coverage.

## Matching and performance requirements

- Match sport, competition, participants and UTC date/start time. Preserve women's,
  youth, replay and qualifying distinctions. Account for renamed/localized teams
  through verified aliases, not unrestricted fuzzy matching.
- A generic programme such as "UEFA Champions League" does not identify a match.
  Do not invent teams or treat a metadata broadcast listing as proof that an IPTV
  channel is showing an event. Retain the programme-time/channel availability checks.
- Keep the guide usable before enrichment. Use cached fixtures and artwork,
  bounded background batches, negative caching and backoff. Never request metadata
  per focus movement, nor probe video streams to find artwork.
- Cache shared fixture metadata through the existing backend; do not expose the
  production API key in clients. Store no playlist credentials in metadata queries.
  Size image decodes for actual cards, not source-image resolution.
- Android and web must share identity rules and fixtures. Verify against the real
  cached playlist: report exact-match coverage separately from fallbacks, and test
  timezones, daylight saving, ambiguous titles, offline mode and missing artwork.

## Production prerequisite

[TheSportsDB terms](https://www.thesportsdb.com/docs_terms_of_use.php) require a paid
subscription for publishing an app-store application, attribution, compliance
with rate limits, and lawful use of third-party content. A subscription is not a
blanket rights grant for every sports trademark or third-party image.

[Published pricing](https://www.thesportsdb.com/pricing) currently lists $9/month
for Single Developer (100 requests/minute) and $20/month for Small Business
(120 requests/minute). Confirm the appropriate plan and artwork permissions for
ARVIO's distributed APK and paid web service before enabling production access.
No subscription was purchased and no shared development key was shipped.
