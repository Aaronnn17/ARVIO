const test = require('node:test');
const assert = require('node:assert/strict');
const mb = require('mediabunny');
const { load } = require('./load.cjs');

// Encoded 16x16 black H.264 samples; timestamps below model a 40-second GOP.
// The worker uses the real MP4 muxer; no browser, ffmpeg, file or provider is needed.
const keyData = Buffer.from('AAAACmWIhDomKAAJAuA=', 'base64');
const deltaData = Buffer.from('AAAABUGaIBSl', 'base64');
const decoderConfig = {
  codec: 'avc1.42c00a', codedWidth: 16, codedHeight: 16,
  description: Buffer.from('AULACv/hABVnQsAK2nsBEAAAAwAQAAADACDxImoBAARozg/I', 'base64')
};
const flush = () => new Promise(setImmediate);

function workerHarness(t, packets, fetch = async () => { throw new Error('Unexpected fetch'); }) {
  const messages = [];
  const waits = [];
  const timers = new Map();
  const outputs = [];
  let options;
  let lastPacketTime;
  const emit = (message) => {
    messages.push(message);
    for (const waiter of [...waits]) {
      if (waiter.predicate(message)) {
        waits.splice(waits.indexOf(waiter), 1);
        waiter.resolve(message);
      }
    }
  };
  const video = {
    codec: 'avc', rotation: 0,
    getCodecParameterString: async () => decoderConfig.codec,
    getDecoderConfig: async () => decoderConfig
  };
  class InputMock {
    async getFormat() { return { name: 'Matroska' }; }
    async getPrimaryVideoTrack() { return video; }
    async getAudioTracks() { return []; }
    async computeDuration() { return 90; }
  }
  class UrlSourceMock {
    constructor(_url, value) { options = value; }
  }
  class PacketSinkMock {
    async getKeyPacket() { return packets[0]; }
    async getFirstPacket() { return packets[0]; }
    async *packets() {
      for (const packet of packets) { lastPacketTime = packet.timestamp; yield packet; }
    }
  }
  class Output extends mb.Output {
    constructor(config) { super(config); outputs.push(this); }
  }
  const port = {
    postMessage(message) {
      emit(message);
      if (message.type === 'chunk') queueMicrotask(() => port.onmessage({ data: { type: 'ack', id: message.id } }));
    }
  };
  load('lib/remux.worker.ts', {
    mediabunny: { ...mb, Input: InputMock, UrlSource: UrlSourceMock, EncodedPacketSink: PacketSinkMock, Output },
    './remuxProtocol': load('lib/remuxProtocol.ts')
  }, {
    self: port, WritableStream, fetch,
    setTimeout: (callback, ms) => {
      const timer = {};
      timers.set(timer, { callback, ms });
      if (ms === 80) emit({ type: 'throttled', timestamp: lastPacketTime });
      return timer;
    },
    clearTimeout: (timer) => timers.delete(timer)
  });
  t.after(async () => {
    for (const output of outputs) if (output.state !== 'finalized') await output.cancel();
    timers.clear();
  });
  return {
    messages, timers,
    options: () => options,
    send: (data) => port.onmessage({ data }),
    waitFor: (predicate) => {
      const message = messages.find(predicate);
      return message ? Promise.resolve(message) : new Promise((resolve) => waits.push({ predicate, resolve }));
    },
    fireTimers: (ms) => {
      for (const [id, timer] of [...timers]) {
        if (timer.ms === ms) { timers.delete(id); timer.callback(); }
      }
    }
  };
}

async function probe(harness) {
  harness.send({ type: 'probe', url: 'https://fixture.invalid/film.mkv', audioCodecs: [] });
  return harness.waitFor(({ type }) => type === 'probe');
}

test('A 40-second GOP emits a real MP4 media fragment before waiting for the playback clock', { timeout: 5000 }, async (t) => {
  const packets = Array.from({ length: 90 }, (_, timestamp) => {
    const key = timestamp % 40 === 0;
    return new mb.EncodedPacket(key ? keyData : deltaData, key ? 'key' : 'delta', timestamp, 1, timestamp);
  });
  const worker = workerHarness(t, packets);
  await probe(worker);
  worker.send({ type: 'start', generation: 0, time: 0, audioIndex: -1 });
  const stopped = await worker.waitFor(({ type }) => type === 'throttled' || type === 'error');
  assert.equal(stopped.type, 'throttled');
  assert.equal(stopped.timestamp, 40, 'Do not stop at a delta packet before the fragment can flush');
  const chunks = worker.messages.filter(({ type }) => type === 'chunk');
  assert.ok(chunks.some(({ data }) => Buffer.from(data).includes(Buffer.from('moof'))), 'A fragment must precede clock-driven throttling');
  assert.equal(worker.messages.some(({ type }) => type === 'end'), false);

  worker.send({ type: 'clock', time: 70 });
  worker.fireTimers(80);
  const finished = await worker.waitFor(({ type }) => type === 'end' || type === 'error');
  assert.equal(finished.type, 'end');
  const output = Buffer.concat(worker.messages.filter(({ type }) => type === 'chunk').map(({ data }) => Buffer.from(data)));
  const input = new mb.Input({ formats: mb.ALL_FORMATS, source: new mb.BufferSource(output) });
  try {
    assert.equal((await input.getFormat()).name, 'MP4');
    assert.equal(await input.computeDuration(), 90);
    const video = await input.getPrimaryVideoTrack();
    assert.equal(video.codec, 'avc');
    const sink = new mb.EncodedPacketSink(video);
    assert.equal((await sink.getKeyPacket(65)).timestamp, 40);
  } finally { input.dispose(); }
});

test('More than 24 MiB of unflushed video fails with an actionable error', { timeout: 5000 }, async (t) => {
  const tooLarge = new mb.EncodedPacket(new Uint8Array(24 * 1024 * 1024 + 1), 'key', 0, 1);
  const worker = workerHarness(t, [tooLarge]);
  await probe(worker);
  worker.send({ type: 'start', generation: 0, time: 0, audioIndex: -1 });
  const result = await worker.waitFor(({ type }) => type === 'error' || type === 'throttled' || type === 'end');
  assert.equal(result.type, 'error');
  assert.match(result.message, /keyframes.*bounded browser playback/i);
  assert.match(result.message, /server conversion or an external player/i);
});

test('Range-ignorant responses are cancelled without retry or a leaked deadline', async (t) => {
  let cancelled = 0;
  const worker = workerHarness(t, [], async () => new Response(new ReadableStream({ cancel() { cancelled++; } }), { status: 200 }));
  await probe(worker);
  const options = worker.options();
  const caller = new AbortController();
  await assert.rejects(options.fetchFn('https://fixture.invalid/film.mkv', {
    headers: { Range: 'bytes=500-' }, signal: caller.signal
  }), /range requests/);
  assert.equal(cancelled, 1);
  assert.equal(options.getRetryDelay(1, new Error('Range unsupported')), null);
  assert.equal(worker.timers.size, 0);
});

test('Fetch headers and stalled range bodies both have 15-second deadlines', async (t) => {
  for (const phase of ['headers', 'body']) {
    let requestSignal;
    const worker = workerHarness(t, [], async (_url, init) => {
      requestSignal = init.signal;
      if (phase === 'headers') return new Promise((_, reject) => {
        init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true });
      });
      return new Response(new ReadableStream({
        start(controller) {
          init.signal.addEventListener('abort', () => controller.error(init.signal.reason), { once: true });
        }
      }), { status: 206, headers: { 'Content-Range': 'bytes 0-999/1000' } });
    });
    await probe(worker);
    const pending = worker.options().fetchFn('https://fixture.invalid/film.mkv', { headers: { Range: 'bytes=0-' } });
    const operation = phase === 'headers' ? pending : (await pending).body.getReader().read();
    const rejected = assert.rejects(operation, /abort/i);
    await flush();
    assert.ok([...worker.timers.values()].some(({ ms }) => ms === 15000));
    worker.fireTimers(15000);
    await rejected;
    assert.equal(requestSignal.aborted, true);
    assert.equal(worker.timers.size, 0);
  }
});
