import { cachedDebridDirectUrl, parseDebridStream, resolveDebridDirectUrl, resolveTranscodeStream } from "./debrid";
import { playbackPlan, canProviderTranscode, canTryRemux, videoDecodableForDevice } from "./streamCompatibility";
import { prepareHomeServerPlayback } from "./homeServerPlayback";
import type { AppSettings, StreamSource } from "./types";

export type PreparePlaybackOptions = { forceRemux?: boolean; forceTranscode?: boolean; signal?: AbortSignal };

export async function prepareBrowserStream(stream: StreamSource, settings: AppSettings, options: PreparePlaybackOptions = {}): Promise<StreamSource> {
  const check = () => { if (options.signal?.aborted) throw new DOMException("Playback cancelled", "AbortError"); };
  check();
  if (!stream.url) throw new Error("This source has no playback URL");
  if (stream.homeServer) {
    return prepareHomeServerPlayback(stream, settings, { forceTranscode: options.forceTranscode || options.forceRemux, signal: options.signal });
  }
  const plan = playbackPlan(stream);
  const debrid = parseDebridStream(stream.originalUrl ?? stream.url);
  if (options.forceTranscode || plan.method === "transcode") {
    if (!debrid || !canProviderTranscode(stream)) throw new Error("This source cannot be converted by its provider. Use an external player.");
    const result = await resolveTranscodeStream(debrid);
    check();
    if (!result.url) throw new Error(result.error ?? "Server conversion is unavailable");
    return { ...stream, url: result.url, originalUrl: stream.originalUrl ?? stream.url, remux: false, transcoded: true, transport: "hls" };
  }
  // Remux changes packaging/audio, not the video codec or Dolby Vision colours.
  if (plan.route !== "here" && (!options.forceRemux || !videoDecodableForDevice(stream))) throw new Error(plan.detail || "This format requires an external player");
  const remux = !!options.forceRemux || plan.method === "remux"
    || (Object.keys(stream.behaviorHints?.proxyHeaders?.request ?? {}).length > 0 && canTryRemux(stream));
  const cached = cachedDebridDirectUrl(stream.originalUrl ?? stream.url);
  let url = cached ?? stream.url;
  if (debrid && remux && !cached) {
    const result = await resolveDebridDirectUrl(debrid);
    check();
    if (!result.url) throw new Error(result.error ?? "The provider could not resolve this source");
    url = result.url;
  }
  return { ...stream, url, originalUrl: stream.originalUrl ?? (url !== stream.url ? stream.url : undefined), remux };
}
