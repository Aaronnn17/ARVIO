import {
  Input, UrlSource, ALL_FORMATS, Output, Mp4OutputFormat, StreamTarget,
  EncodedPacketSink, EncodedVideoPacketSource, EncodedAudioPacketSource,
  AudioSampleSink, AudioSampleSource,
} from "mediabunny";
import { preferredAudioIndex, type RemuxCommand, type RemuxEvent, type RemuxProbe } from "./remuxProtocol";

const port = self as unknown as { postMessage: (message: RemuxEvent, transfer?: Transferable[]) => void; onmessage: ((event: MessageEvent<RemuxCommand>) => void) | null };
let input: Input;
let probe: RemuxProbe;
let generation = 0;
let clock = 0;
let output: Output | undefined;
let nextId = 0;
let aacEncoderRegistered = false;
const acknowledgements = new Map<number, () => void>();
const sleep = () => new Promise<void>((resolve) => setTimeout(resolve, 80));

async function probeInput(command: Extract<RemuxCommand, { type: "probe" }>) {
  input = new Input({ formats: ALL_FORMATS, source: new UrlSource(command.url, {
    maxCacheSize: 8 * 1024 * 1024,
    getRetryDelay: () => null,
    requestInit: { headers: command.headers },
    fetchFn: async (url, init) => {
      const controller = new AbortController();
      const abort = () => controller.abort();
      init?.signal?.addEventListener("abort", abort, { once: true });
      if (init?.signal?.aborted) controller.abort();
      let timer = setTimeout(abort, 15000);
      const response = await fetch(url, { ...init, signal: controller.signal }).catch((error) => {
        clearTimeout(timer); init?.signal?.removeEventListener("abort", abort); throw error;
      });
      clearTimeout(timer);
      // Range-ignorant hosts otherwise cause UrlSource to cache a whole multi-GB file.
      if (new Headers(init?.headers).has("range") && response.status !== 206) {
        await response.body?.cancel();
        init?.signal?.removeEventListener("abort", abort);
        throw new Error("This source does not support browser range requests");
      }
      if (!response.body) { init?.signal?.removeEventListener("abort", abort); return response; }
      const reader = response.body.getReader();
      const finish = () => { clearTimeout(timer); init?.signal?.removeEventListener("abort", abort); };
      return new Response(new ReadableStream({
        async pull(sink) {
          timer = setTimeout(abort, 15000);
          try {
            const next = await reader.read();
            clearTimeout(timer);
            if (next.done) { finish(); sink.close(); } else sink.enqueue(next.value);
          } catch (error) { finish(); sink.error(error); }
        },
        cancel(reason) { finish(); controller.abort(); return reader.cancel(reason); }
      }), { status: response.status, statusText: response.statusText, headers: response.headers });
    }
  }) });
  const format = await input.getFormat();
  const video = await input.getPrimaryVideoTrack();
  if (!video) throw new Error("No supported video track found");
  const tracks = await input.getAudioTracks();
  if (tracks.some((track) => /ac3|eac3/.test(track.codec ?? ""))) {
    (await import("@mediabunny/ac3")).registerAc3Decoder();
  }
  if (tracks.some((track) => /dts/.test(track.codec ?? ""))) {
    (await import("@mediabunny/dts")).registerDtsDecoder();
  }
  const audioTracks = [];
  for (const [index, track] of tracks.entries()) {
    const codec = await track.getCodecParameterString() ?? track.codec ?? "unknown";
    const passthrough = command.audioCodecs.includes(codec);
    const browserPlayable = passthrough || await track.canDecode();
    audioTracks.push({ index, codec, passthrough, browserPlayable,
      language: track.languageCode ?? undefined, channels: track.numberOfChannels,
      label: [track.languageCode?.toUpperCase(), codec.toUpperCase(), `${track.numberOfChannels}ch`, !passthrough && browserPlayable ? "converted" : ""].filter(Boolean).join(" / ") });
  }
  probe = { container: format.name, videoCodec: await video.getCodecParameterString() ?? undefined,
    videoPlayable: true, audioTracks, chosenAudioIndex: preferredAudioIndex(audioTracks, command.language),
    duration: await input.computeDuration() };
  port.postMessage({ type: "probe", probe });
}

async function produce(command: Extract<RemuxCommand, { type: "start" }>) {
  const run = command.generation;
  generation = run;
  clock = command.time;
  for (const resolve of acknowledgements.values()) resolve();
  acknowledgements.clear();
  const previous = output;
  output = undefined;
  await previous?.cancel();
  if (run !== generation) return;
  const active = () => run === generation;
  const throttle = async (timestamp: number) => {
    while (active() && timestamp > clock + 25) await sleep();
    if (!active()) throw new Error("Cancelled");
  };
  let videoTimestamp = command.time;
  let videoFinished = false;
  let fragmentBytes = 0;
  const video = await input.getPrimaryVideoTrack();
  if (!video?.codec) throw new Error("Unsupported video codec");
  const videoSink = new EncodedPacketSink(video);
  const first = await videoSink.getKeyPacket(command.time) ?? await videoSink.getFirstPacket();
  if (!first) throw new Error("No video keyframe found");
  const audio = (await input.getAudioTracks())[command.audioIndex];
  const transcode = !!audio && !probe.audioTracks[command.audioIndex].passthrough;
  if (transcode && !aacEncoderRegistered) {
    (await import("@mediabunny/aac-encoder")).registerAacEncoder();
    aacEncoderRegistered = true;
  }
  if (!active()) return;
  const target = new StreamTarget(new WritableStream({
    async write(chunk: { data: Uint8Array }) {
      if (!active()) throw new Error("Cancelled");
      const data = chunk.data.slice().buffer;
      const id = ++nextId;
      await new Promise<void>((resolve) => {
        acknowledgements.set(id, resolve);
        port.postMessage({ type: "chunk", generation: run, id, data }, [data]);
      });
    }
  }));
  const current = new Output({ format: new Mp4OutputFormat({ fastStart: "fragmented", minimumFragmentDuration: 1,
    onMoof: () => { fragmentBytes = 0; }
  }), target });
  output = current;
  const videoSource = new EncodedVideoPacketSource(video.codec);
  current.addVideoTrack(videoSource, { rotation: video.rotation });
  const audioSource = audio?.codec ? transcode
    ? new AudioSampleSource({ codec: "aac", bitrate: 192000, transform: { numberOfChannels: 2, sampleRate: 48000 } })
    : new EncodedAudioPacketSource(audio.codec) : undefined;
  if (audioSource) current.addAudioTrack(audioSource);
  await current.start();
  const videoConfig = await video.getDecoderConfig();
  // Both tracks retain their original timestamps. Seeking reads at the preceding
  // keyframe without re-encoding video or converting the earlier part of the file.
  const videoTask = async () => {
    for await (const packet of videoSink.packets(first)) {
      if (!active()) throw new Error("Cancelled");
      videoTimestamp = Math.max(videoTimestamp, packet.timestamp);
      fragmentBytes += packet.data.byteLength;
      if (fragmentBytes > 24 * 1024 * 1024) throw new Error("Keyframes are too far apart for bounded browser playback. Use server conversion or an external player.");
      await videoSource.add(packet, videoConfig ? { decoderConfig: videoConfig } : undefined);
      // Only pause after a keyframe has flushed the preceding fragment. Pausing
      // halfway through a long GOP would wait for a playhead that cannot advance.
      if (packet.type === "key") await throttle(packet.timestamp);
    }
    videoFinished = true;
    videoSource.close();
  };
  const audioTask = async () => {
    if (!audio || !audioSource) return;
    if (audioSource instanceof AudioSampleSource) {
      for await (const sample of new AudioSampleSink(audio).samples(first.timestamp)) {
        try {
          while (active() && !videoFinished && sample.timestamp > videoTimestamp + 2) await sleep();
          if (videoFinished) await throttle(sample.timestamp);
          if (!active()) throw new Error("Cancelled");
          await audioSource.add(sample);
        }
        finally { sample.close(); }
      }
    } else {
      const sink = new EncodedPacketSink(audio);
      const start = await sink.getPacket(first.timestamp) ?? await sink.getFirstPacket();
      const config = await audio.getDecoderConfig();
      if (start) for await (const packet of sink.packets(start)) {
        while (active() && !videoFinished && packet.timestamp > videoTimestamp + 2) await sleep();
        if (videoFinished) await throttle(packet.timestamp);
        if (!active()) throw new Error("Cancelled");
        await audioSource.add(packet, config ? { decoderConfig: config } : undefined);
      }
    }
    audioSource.close();
  };
  await Promise.all([videoTask(), audioTask()]);
  if (!active()) return;
  await current.finalize();
  port.postMessage({ type: "end", generation: run });
}

port.onmessage = ({ data }) => {
  if (data.type === "clock") { clock = data.time; return; }
  if (data.type === "ack") { acknowledgements.get(data.id)?.(); acknowledgements.delete(data.id); return; }
  const run = data.type === "start" ? data.generation : 0;
  void (data.type === "probe" ? probeInput(data) : produce(data)).catch((error: unknown) => {
    if (run !== generation) return;
    port.postMessage({ type: "error", generation: run, message: error instanceof Error ? error.message : "Browser conversion failed" });
  });
};
