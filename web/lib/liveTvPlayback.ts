// How a Live TV (IPTV) channel is played in the browser, as pure decisions:
//   - what shape the channel URL is (HLS, raw MPEG-TS, a file, or opaque),
//   - which engines this browser has for that shape (native HLS, hls.js,
//     mpegts.js over MediaSource / ManagedMediaSource, the plain <video>),
//   - which routes can reach it (direct, the resolver relay, the manifest
//     relay through the app backend), skipping the ones that cannot work,
//   - and, when nothing plays, the one reason worth telling the viewer.
//
// The player (components/player/overlay/usePlaybackEngine.ts) walks the plan.
// Keeping the rules here lets every (browser, stream shape) combination be
// tested without a browser. See tests/live-tv-playback.test.cjs.
import type { PlaybackError, PlaybackMediaInfo, PlaybackTransport } from "./player";

export type LiveShape = "hls" | "mpegts" | "dash" | "file" | "unknown";
export type LiveRoute = "direct" | "relay" | "manifest-relay" | "app-proxy";
export type HlsEngine = "native" | "mse";

export type LiveEnvironment = {
  /** location.protocol of the app page ("https:" in production). */
  pageProtocol: string;
  /** MediaSource or ManagedMediaSource: hls.js, mpegts.js and dash.js need it. */
  mse: boolean;
  /** <video> plays HLS itself (Safari, iOS, some TV browsers). */
  nativeHls: boolean;
  /** Apple browsers, where native HLS is preferred over hls.js when both exist. */
  preferNativeHls: boolean;
};

export type LiveRoutes = {
  /** The resolver worker's /media relay (CORS, headers, http → https). */
  relay?: (url: string) => string | null;
  /** HLS playlist through the app backend, segments through the relay (hosts that block Cloudflare). */
  manifestRelay?: (url: string) => string | null;
  /** The Netlify media proxy, only when a deployment explicitly allows it. */
  appProxy?: (url: string) => string | null;
};

export type LiveAttempt = {
  url: string;
  transport: PlaybackTransport;
  /** For HLS: force the browser's own player or hls.js. */
  hlsEngine?: HlsEngine;
  route: LiveRoute;
  /** The provider URL this attempt reaches (before relaying). */
  target: string;
  variant: "original" | "twin";
  /** Headers the engine itself may send (direct requests only). */
  headers?: Record<string, string>;
  /** Startup deadline override (ms without metadata). */
  startupMs?: number;
};

export type LivePlan = { attempts: LiveAttempt[]; blocked?: "insecure" | "no-engine" };

export type LiveFailureKind =
  | "insecure" | "relay-denied" | "provider-refused" | "provider-busy" | "offline" | "provider-down"
  | "codec-audio" | "codec-video" | "codec" | "unsupported-browser" | "no-data" | "network" | "stopped";

export type LiveFailure = {
  kind: LiveFailureKind;
  /** Short heading, an English UI phrase (translated by the screen). */
  title: string;
  /** What happened and what to do next; may use {value0}/{value1} placeholders. */
  message: string;
  values?: Record<string, string | number>;
};

export type LiveFault = { attempt: LiveAttempt; fault?: PlaybackError };

/**
 * Marks a phrase for the i18n catalog (scripts/translation-sources.mjs collects
 * translateUi("…") literals). The player screen translates it when shown.
 */
const translateUi = (text: string) => text;
/** Phrases the player shows for Live TV outside this module (values, status lines, toasts). */
export const LIVE_PHRASES = [translateUi("this browser"), translateUi("Reconnecting to the channel…"), translateUi("Refreshing the channel link…"),
  translateUi("Other ways to watch")];

function parse(url: string) {
  try { return new URL(url); } catch { return null; }
}

function decodedPath(url: URL) {
  try { return decodeURIComponent(url.pathname).toLowerCase(); } catch { return url.pathname.toLowerCase(); }
}

const VOD_PREFIXES = new Set(["movie", "movies", "series", "vod", "timeshift", "streaming", "hls", "media", "api"]);

/**
 * What a channel URL carries. Mirrors Android (IptvPlaybackUrlResolver /
 * buildXtreamLiveStreamUrl): `.m3u8`, `/hls/`, `output=m3u8` mean HLS; `.ts`,
 * numeric Xtream ids and Stalker `play/live.php?…&extension=ts` are raw
 * MPEG-TS; anything else is opaque and has to be found out by trying.
 */
export function liveStreamShape(url: string): LiveShape {
  const parsed = parse(url);
  if (!parsed) return "unknown";
  const path = decodedPath(parsed);
  if (/\.m3u8?$/.test(path)) return "hls";
  if (/\.mpd$/.test(path)) return "dash";
  if (/\.(ts|m2ts|mts|mpegts)$/.test(path)) return "mpegts";
  if (/\.(mp4|m4v|mov|mkv|webm|mp3|aac|m4a|ogg|oga|opus|flac|wav)$/.test(path)) return "file";
  const query = [...parsed.searchParams].filter(([name]) => /^(extension|ext|output|format|type|container)$/i.test(name)).map(([, value]) => value.toLowerCase());
  if (query.some((value) => value === "m3u8" || value === "hls" || value === "m3u")) return "hls";
  if (query.some((value) => value === "ts" || value === "mpegts" || value === "mp2t")) return "mpegts";
  if (/\/hls\//.test(path)) return "hls";
  if (/\/play\/live\.php$/.test(path)) return "mpegts";
  const segments = path.split("/").filter(Boolean);
  // Xtream live ids: /live/user/pass/123 and the short /user/pass/123 form.
  if (/^\d+$/.test(segments.at(-1) ?? "") && (segments[0] === "live" ? segments.length === 4 : segments.length === 3 && !VOD_PREFIXES.has(segments[0]))) return "mpegts";
  return "unknown";
}

/**
 * The same Xtream channel in its other output format: panels serve every live
 * channel as `/live/u/p/<id>.ts` and `/live/u/p/<id>.m3u8`, but some refuse
 * one of them (allowed_output_formats). Query strings are kept as they are.
 */
export function xtreamTwinUrl(url: string): string | null {
  const parsed = parse(url);
  if (!parsed || !/^https?:$/.test(parsed.protocol)) return null;
  const segments = parsed.pathname.split("/").filter(Boolean);
  let prefix: string[];
  let last: string;
  if (segments.length === 4 && segments[0].toLowerCase() === "live") { prefix = segments.slice(0, 3); last = segments[3]; }
  else if (segments.length === 3 && !VOD_PREFIXES.has(segments[0].toLowerCase()) && segments[0].toLowerCase() !== "live" && /^\d+(\.ts)?$/i.test(segments[2])) { prefix = ["live", ...segments.slice(0, 2)]; last = segments[2]; }
  else return null;
  const match = last.match(/^(\d+)(?:\.(ts|m3u8))?$/i);
  if (!match) return null;
  const twin = new URL(parsed.toString());
  const extension = match[2]?.toLowerCase() === "m3u8" ? "ts" : "m3u8";
  twin.pathname = `/${[...prefix, `${match[1]}.${extension}`].join("/")}`;
  return twin.toString();
}

function trustworthyHost(host: string) {
  const name = host.replace(/^\[|\]$/g, "").toLowerCase();
  return name === "localhost" || name.endsWith(".localhost") || name === "::1" || /^127\./.test(name);
}

/** A secure page cannot load this URL: every engine blocks or breaks it (mixed content). */
export function isInsecureForPage(url: string, pageProtocol: string) {
  const parsed = parse(url);
  return !!parsed && pageProtocol === "https:" && parsed.protocol === "http:" && !trustworthyHost(parsed.hostname);
}

/** Headers a browser will not send itself; a provider that needs them must be relayed. */
export function needsRelayForHeaders(headers?: Record<string, string>) {
  return Object.keys(headers ?? {}).some((name) => /^(referer|origin|user-agent|cookie|host)$/i.test(name));
}

function browserSendableHeaders(headers?: Record<string, string>) {
  const kept = Object.entries(headers ?? {}).filter(([name]) => !/^(referer|origin|user-agent|cookie|host|icy-metadata)$/i.test(name));
  return kept.length ? Object.fromEntries(kept) : undefined;
}

type Choice = { transport: PlaybackTransport; hlsEngine?: HlsEngine };

/** Engines this browser has for a shape, best first. Empty = cannot play here. */
export function engineChoices(shape: LiveShape, env: LiveEnvironment): Choice[] {
  const hls: Choice[] = env.nativeHls && env.mse
    ? env.preferNativeHls
      // Safari: AVFoundation first (hardware, AirPlay), hls.js when it refuses the stream.
      ? [{ transport: "hls", hlsEngine: "native" }, { transport: "hls", hlsEngine: "mse" }]
      : [{ transport: "hls", hlsEngine: "mse" }, { transport: "hls", hlsEngine: "native" }]
    : env.nativeHls ? [{ transport: "hls", hlsEngine: "native" }] : env.mse ? [{ transport: "hls", hlsEngine: "mse" }] : [];
  switch (shape) {
    case "hls": return hls;
    case "mpegts": return env.mse ? [{ transport: "mpegts" }] : [];
    case "dash": return env.mse ? [{ transport: "dash" }] : [];
    case "file": return [{ transport: "file" }];
    default:
      // Opaque live URLs are raw TS far more often than anything else; a
      // playlist is rejected by mpegts.js at once (FormatUnsupported).
      return [...(env.mse ? [{ transport: "mpegts" } as Choice] : []), ...hls.slice(0, 1), { transport: "file" }];
  }
}

const MAX_ATTEMPTS = 10;

/** The ordered attempts for one channel. */
export function planLiveAttempts(source: { url: string; headers?: Record<string, string> }, env: LiveEnvironment, routes: LiveRoutes): LivePlan {
  const headerRelay = needsRelayForHeaders(source.headers);
  const twin = xtreamTwinUrl(source.url);
  const targets = [{ url: source.url, variant: "original" as const }, ...(twin ? [{ url: twin, variant: "twin" as const }] : [])]
    .map((target) => ({ ...target, choices: engineChoices(liveStreamShape(target.url), env) }))
    .filter((target) => target.choices.length > 0);
  if (!targets.length) return { attempts: [], blocked: "no-engine" };
  const attempts: LiveAttempt[] = [];
  const add = (attempt: LiveAttempt | null) => {
    if (attempt && !attempts.some((existing) => existing.url === attempt.url && existing.transport === attempt.transport && existing.hlsEngine === attempt.hlsEngine)) attempts.push(attempt);
  };
  const reachable = (url: string) => !isInsecureForPage(url, env.pageProtocol);
  const direct = (target: (typeof targets)[number], choice: Choice, extra: Partial<LiveAttempt> = {}): LiveAttempt => ({
    url: target.url, ...choice, route: "direct", target: target.url, variant: target.variant, headers: browserSendableHeaders(source.headers), ...extra
  });
  // 1. Direct: free, and the subscriber's own IP. Not for http:// on the
  //    secure page (blocked everywhere; WebKit does not even report it), and
  //    not first when the provider needs headers a browser cannot send.
  if (!headerRelay) for (const target of targets) if (reachable(target.url)) for (const choice of target.choices) add(direct(target, choice));
  // 2. The relay, for each form of the channel and each engine.
  if (routes.relay) for (const target of targets) {
    const relayed = routes.relay(target.url);
    if (relayed) for (const choice of target.choices) add({ url: relayed, ...choice, route: "relay", target: target.url, variant: target.variant });
  }
  // 3. HLS playlists through the app backend (providers that block Cloudflare).
  //    Known playlists only: the backend must never be handed an opaque URL
  //    that may turn out to be a raw TS stream (hosting bandwidth).
  if (routes.manifestRelay) for (const target of targets) {
    if (liveStreamShape(target.url) !== "hls") continue;
    const relayed = routes.manifestRelay(target.url);
    const choice = engineChoices("hls", env)[0];
    if (relayed && choice) add({ url: relayed, ...choice, route: "manifest-relay", target: target.url, variant: target.variant });
  }
  // 4. Header-dependent providers sometimes accept the browser anyway.
  if (headerRelay) for (const target of targets) if (reachable(target.url)) add(direct(target, target.choices[0]));
  // 5. Without any relay, Safari before 18 still loads http:// media natively.
  if (!routes.relay && env.nativeHls) for (const target of targets) {
    const native = target.choices.find((choice) => choice.hlsEngine === "native");
    if (native && !reachable(target.url)) add(direct(target, native, { startupMs: 6000 }));
  }
  if (routes.appProxy) {
    const proxied = routes.appProxy(targets[0].url);
    if (proxied) add({ url: proxied, ...targets[0].choices[0], route: "app-proxy", target: targets[0].url, variant: targets[0].variant });
  }
  if (!attempts.length) return { attempts, blocked: "insecure" };
  return { attempts: attempts.slice(0, MAX_ATTEMPTS) };
}

/**
 * An attempt that cannot succeed given what earlier attempts proved: the
 * provider answered this exact URL over this route with an HTTP error, so a
 * different engine for the same request would only repeat it.
 */
export function attemptIsPointless(attempt: LiveAttempt, previous: LiveFault[]) {
  return previous.some(({ attempt: earlier, fault }) => earlier.url === attempt.url && earlier.route === attempt.route
    && typeof fault?.httpStatus === "number" && fault.httpStatus >= 400);
}

const AUDIO_LABELS: [RegExp, string][] = [
  [/^(ac-?3|a52)/i, "Dolby Digital (AC-3)"], [/^(ec-?3|e-?ac-?3)/i, "Dolby Digital Plus (E-AC-3)"],
  [/^(mp3|mp4a\.6b|mp4a\.69|mpga|mp2)/i, "MPEG audio (MP2/MP3)"], [/^(mp4a|aac)/i, "AAC"], [/^opus/i, "Opus"], [/^dts|^dtsc/i, "DTS"]
];
const VIDEO_LABELS: [RegExp, string][] = [
  [/^(hvc1|hev1|hevc|h265)/i, "HEVC (H.265)"], [/^(avc|h264)/i, "H.264"], [/^(mpeg2|mp2v|mp4v\.6[0-5]|mp4v\.61)/i, "MPEG-2"],
  [/^(vp09|vp9)/i, "VP9"], [/^(av01|av1)/i, "AV1"]
];
export function codecLabel(codec: string | undefined, kind: "audio" | "video") {
  const value = (codec ?? "").trim();
  for (const [pattern, label] of kind === "audio" ? AUDIO_LABELS : VIDEO_LABELS) if (pattern.test(value)) return label;
  return value || (kind === "audio" ? translateUi("an unknown audio format") : translateUi("an unknown video format"));
}

/** `canDecode` for a browser, from MediaSource.isTypeSupported / canPlayType. */
export function decodeCheck(isTypeSupported: (type: string) => boolean) {
  return (kind: "audio" | "video", codec: string) => {
    const value = codec.trim();
    if (!value) return true;
    // MPEG audio rides in its own SourceBuffer type in Chromium, in MP4 in Firefox.
    if (kind === "audio" && /^(mp3|mp4a\.6b|mp4a\.69|mpga)$/i.test(value)) return isTypeSupported("audio/mpeg") || isTypeSupported('audio/mp4; codecs="mp3"');
    return isTypeSupported(`${kind}/mp4; codecs="${value}"`);
  };
}

/** The browser's everyday name, for sentences such as "Firefox can't decode…". */
export function browserName(userAgent: string) {
  if (/SamsungBrowser/i.test(userAgent)) return "Samsung Internet";
  if (/Edg(e|A|iOS)?\//.test(userAgent)) return "Edge";
  if (/OPR\/|Opera/.test(userAgent)) return "Opera";
  if (/Firefox\/|FxiOS/.test(userAgent)) return "Firefox";
  if (/Chrome\/|CriOS|Chromium/.test(userAgent)) return "Chrome";
  // Includes iOS home-screen apps, whose user agent has no Safari token.
  if (/Safari\//.test(userAgent) || (/(iPhone|iPad|iPod|Macintosh)/.test(userAgent) && /AppleWebKit/.test(userAgent))) return "Safari";
  return "this browser";
}

export type LiveFailureContext = {
  browser: string;
  /** Whether this browser decodes a codec in MSE/native playback. */
  canDecode?: (kind: "audio" | "video", codec: string) => boolean;
  /** The channel URL is http:// on the secure page. */
  insecureSource: boolean;
  /** A relay route exists in this deployment. */
  relayAvailable: boolean;
  /** The relay was sent a Premium stream ticket. */
  relayTicket: boolean;
  /** The channel played before it failed. */
  played: boolean;
};

function codecFailure(info: PlaybackMediaInfo | undefined, context: LiveFailureContext): LiveFailure | null {
  if (!info) return null;
  const canDecode = context.canDecode ?? (() => true);
  const browser = context.browser;
  const safari = browser === "Safari";
  if (info.videoCodec && /^(mpeg2|mp2v)/i.test(info.videoCodec)) {
    return { kind: "codec-video", title: translateUi("Video format not supported"), message: translateUi("This channel's video is MPEG-2, which no web browser can decode. Watch it in the ARVIO app or VLC.") };
  }
  if (info.videoCodec && !canDecode("video", info.videoCodec)) {
    const label = codecLabel(info.videoCodec, "video");
    return { kind: "codec-video", title: translateUi("Video format not supported"), values: { value0: label, value1: browser },
      message: safari || !/HEVC/.test(label) ? translateUi("This channel's video is {value0}, which {value1} can't decode. Watch it in the ARVIO app or VLC.") : translateUi("This channel's video is {value0}, which {value1} can't decode on this device. Try Safari, or watch it in the ARVIO app.") };
  }
  if (info.audioCodec && !canDecode("audio", info.audioCodec)) {
    const label = codecLabel(info.audioCodec, "audio");
    return { kind: "codec-audio", title: translateUi("Audio format not supported"), values: { value0: label, value1: browser },
      message: safari || !/Dolby/.test(label) ? translateUi("This channel's audio is {value0}, which {value1} can't decode. Watch it in the ARVIO app or VLC.") : translateUi("This channel's audio is {value0}, which {value1} can't decode. It plays with sound in Safari and in the ARVIO app.") };
  }
  return null;
}

/**
 * Proof that media arrived and this browser could not decode it. A MediaSource
 * engine's media error is; so is the element's MEDIA_ERR_DECODE. The element's
 * MEDIA_ERR_SRC_NOT_SUPPORTED is not: browsers also report refused, blocked and
 * missing sources that way.
 */
function isDecodeFault({ attempt, fault }: LiveFault) {
  if (!fault) return false;
  const native = attempt.transport === "file" || (attempt.transport === "hls" && attempt.hlsEngine === "native");
  return native ? fault.code === 3 : fault.kind === "media";
}

/** The single most useful explanation for a channel whose attempts all failed. */
export function classifyLiveFailure(faults: LiveFault[], context: LiveFailureContext, blocked?: LivePlan["blocked"]): LiveFailure {
  if (blocked === "no-engine") return { kind: "unsupported-browser", title: translateUi("Not playable in this browser"), values: { value0: context.browser },
    message: translateUi("This channel is sent as a raw MPEG-TS stream, which {value0} on this device can't play (on iPhone it needs iOS 17.1 or later). Update the system, or watch it in the ARVIO app.") };
  if (blocked === "insecure") return { kind: "insecure", title: translateUi("Blocked by browser security"),
    message: translateUi("This channel is only offered over an insecure http:// connection, which browsers don't load inside a secure page, and the ARVIO stream relay isn't available here. Watch it in the ARVIO app or VLC.") };
  const statuses = faults.flatMap(({ attempt, fault }) => typeof fault?.httpStatus === "number" && fault.httpStatus >= 400 ? [{ status: fault.httpStatus, attempt }] : []);
  // The relay refusing the session itself: it answers 402 when the Premium
  // stream ticket is missing or expired (providers never send 402).
  if (statuses.some(({ status, attempt }) => status === 402 && attempt.route !== "direct")) {
    return { kind: "relay-denied", title: translateUi("Stream relay unavailable"),
      message: context.relayTicket
        ? translateUi("ARVIO's stream relay didn't accept this session, so the channel can't be loaded securely. Reload the page, then retry.")
        : translateUi("ARVIO's stream relay didn't accept this session, so the channel can't be loaded securely. Make sure you're signed in with ARVIO Premium, then retry.") };
  }
  // Media that arrived but could not be decoded is the answer, even when the
  // channel's other form (the Xtream twin) was refused.
  const decodeFaults = faults.filter(isDecodeFault);
  if (decodeFaults.length) {
    for (const { fault } of decodeFaults) {
      const verdict = codecFailure(fault?.mediaInfo, context);
      if (verdict) return verdict;
    }
    return { kind: "codec", title: translateUi("Format not supported"), values: { value0: context.browser },
      message: context.browser === "Safari"
        ? translateUi("This channel uses a video or audio format {value0} can't decode. Watch it in the ARVIO app or VLC.")
        : translateUi("This channel uses a video or audio format {value0} can't decode. Try Safari, or watch it in the ARVIO app.") };
  }
  if (statuses.length) {
    // Prefer what the provider said through the relay over CORS-era direct noise.
    const { status } = statuses.find(({ attempt }) => attempt.route !== "direct") ?? statuses[0];
    if (status === 404 || status === 410) return { kind: "offline", title: translateUi("Channel offline"), values: { value0: status },
      message: translateUi("The provider says this channel isn't available right now (HTTP {value0}). It may be offline or moved; try again later or refresh the playlist in Settings.") };
    if (status === 429) return { kind: "provider-busy", title: translateUi("Too many connections"), values: { value0: status },
      message: translateUi("The IPTV provider is limiting connections right now (HTTP {value0}). Stop playback on your other devices, wait a minute, then retry.") };
    if (status >= 500) return { kind: "provider-down", title: translateUi("Provider unavailable"), values: { value0: status },
      message: translateUi("The IPTV provider's server isn't responding (HTTP {value0}). Try again in a few minutes.") };
    return { kind: "provider-refused", title: translateUi("The provider refused this channel"), values: { value0: status },
      message: translateUi("The IPTV provider refused the connection (HTTP {value0}). The subscription may have expired, the connection limit may be reached (stop playback on other devices), or the link expired. Retry, or refresh the playlist in Settings.") };
  }
  if (context.played) return { kind: "stopped", title: translateUi("The channel stopped"),
    message: translateUi("The channel stopped sending video and could not be reconnected. Retry, or try again later.") };
  if (faults.length && faults.every(({ fault }) => fault?.code === "STARTUP_TIMEOUT")) return { kind: "no-data", title: translateUi("No video from the provider"),
    message: translateUi("The provider accepted the connection but sent no video. The channel may be offline or overloaded; try again in a minute.") };
  if (context.insecureSource && !context.relayAvailable) return classifyLiveFailure([], context, "insecure");
  return { kind: "network", title: translateUi("Connection problem"),
    message: translateUi("The channel's server couldn't be reached. Check your internet connection, then retry. If it keeps failing, the channel may be offline.") };
}

/** What a few seconds of live playback showed. */
export type LiveObservation = {
  /** The element has decoded a picture (videoWidth > 0). */
  picture: boolean;
  /** Audio is being decoded: true/false where the browser can tell, null where it cannot. */
  sound: boolean | null;
  info?: PlaybackMediaInfo | null;
};

/**
 * A non-fatal notice once a channel plays but part of it cannot be shown:
 * radio channels and MPEG-2 video arrive without a picture (the engines drop
 * a video track they cannot decode), Dolby audio in Chrome/Firefox arrives
 * without sound (hls.js drops it silently).
 */
export function liveMediaNotice(observed: LiveObservation, context: Pick<LiveFailureContext, "browser" | "canDecode">): { message: string; values?: Record<string, string> } | null {
  const canDecode = context.canDecode ?? (() => true);
  if (!observed.picture) return { message: translateUi("No picture: this channel sends no video {value0} can show. It may be a radio channel, or use MPEG-2 video, which browsers can't decode."), values: { value0: context.browser } };
  const codec = observed.info?.audioCodec;
  if (codec && !canDecode("audio", codec)) {
    return { message: translateUi("No sound: this channel's audio is {value0}, which {value1} can't decode. Safari and the ARVIO app play it with sound."), values: { value0: codecLabel(codec, "audio"), value1: context.browser } };
  }
  // Safari decodes every broadcast audio format; silence there is the channel's own.
  if (observed.sound === false && context.browser !== "Safari") {
    return { message: translateUi("No sound: {value0} can't decode this channel's audio (usually Dolby Digital). Safari and the ARVIO app play it with sound."), values: { value0: context.browser } };
  }
  return null;
}

/** Codec strings from an engine message such as `audio/mp4;codecs="ac-3"`. */
export function mediaInfoFromMime(text: string | undefined): PlaybackMediaInfo | undefined {
  const match = (text ?? "").match(/(audio|video)\/[\w.+-]+;\s*codecs?=\\?"?([^"',)\\]+)/i);
  if (!match) return undefined;
  const codec = match[2].trim();
  return match[1].toLowerCase() === "audio" ? { audioCodec: codec } : { videoCodec: codec.split(",")[0].trim() };
}
