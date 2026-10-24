import { cachedDebridDirectUrl, parseDebridStream } from "./debrid";
import { playbackPlan, streamTransport } from "./streamCompatibility";
import { cachedVerdict, verifyTopSources } from "./streamVerify";
import type { StreamSource } from "./types";

type ProbeGlobals = { VideoDecoder?: unknown; AudioDecoder?: unknown };

/**
 * The URL a pre-play probe may read for this candidate, or null when probing
 * it would be pointless or have side effects:
 *
 * - Only sources the plan will DIRECT-play. Remux/transcode paths read the
 *   container themselves, and the verdict (WebCodecs decoders, without the
 *   app's AC-3/DTS/AAC fallbacks registered) would wrongly reject them.
 * - Unresolved debrid links are skipped: resolving one creates a provider-side
 *   download (TorBox/RD), which browsing and probing must never do. A link the
 *   user already resolved this session is probed through its cached CDN URL.
 * - Sources that need custom request headers or are not plain files (HLS,
 *   IPTV, home-server sessions) are skipped; mediabunny cannot represent them.
 */
export function probeUrlFor(stream: StreamSource): string | null {
  if (!stream.url || stream.homeServer || stream.remux || stream.transcoded) return null;
  if (stream.behaviorHints?.proxyHeaders?.request && Object.keys(stream.behaviorHints.proxyHeaders.request).length) return null;
  if (streamTransport(stream) !== "file") return null;
  if (playbackPlan(stream).method !== "direct") return null;
  if (parseDebridStream(stream.originalUrl ?? stream.url)) return cachedDebridDirectUrl(stream.originalUrl ?? stream.url);
  return /^https?:\/\//i.test(stream.url) ? stream.url : null;
}

/** Probing is only meaningful where the browser exposes WebCodecs decoders. */
export function canProbeDecoders(scope: ProbeGlobals = globalThis as ProbeGlobals) {
  return typeof scope.VideoDecoder === "function" && typeof scope.AudioDecoder === "function";
}

/**
 * Verify the leading autoplay candidates with the (previously unused)
 * streamVerify probe, inside a hard time budget. Returns true/false per
 * candidate when the probe was conclusive, null otherwise.
 */
export async function verifyAutoplayCandidates(candidates: StreamSource[], budgetMs: number, signal: AbortSignal) {
  const verdicts = new Map<StreamSource, boolean | null>();
  for (const stream of candidates) verdicts.set(stream, null);
  if (!canProbeDecoders()) return verdicts;
  const targets = candidates.map((stream) => ({ stream, url: probeUrlFor(stream) }));
  const probeable = targets.filter((target): target is { stream: StreamSource; url: string } => Boolean(target.url));
  if (!probeable.length) return verdicts;
  let timer: ReturnType<typeof setTimeout> | undefined;
  await Promise.race([
    verifyTopSources(probeable.map(({ url }) => ({ url })), probeable.length, probeable.length, signal).catch(() => undefined),
    new Promise<void>((resolve) => { timer = setTimeout(resolve, budgetMs); })
  ]);
  if (timer) clearTimeout(timer);
  for (const { stream, url } of probeable) {
    const verdict = cachedVerdict(url);
    if (!verdict) continue;
    // WebCodecs audio support is narrower than <video>'s (Safari plays AC-3 /
    // E-AC-3 natively but its AudioDecoder may not report them), so an
    // audio-only failure is inconclusive for ranking; only video counts.
    if (!verdict.playable && verdict.videoOk && !verdict.audioOk) continue;
    verdicts.set(stream, verdict.playable);
  }
  return verdicts;
}
