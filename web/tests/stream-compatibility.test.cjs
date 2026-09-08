const test = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('./load.cjs');

const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/145.0.0.0 Safari/537.36';
const FIREFOX = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:145.0) Gecko/20100101 Firefox/145.0';
const debrid = load('lib/debrid.ts', { './http': {} });

function compatibility(overrides = {}, userAgent = FIREFOX) {
  const caps = {
    mse: true, nativeHls: false, h264: true, hevc: false, hevc10: false,
    dolbyVision: false, av1: true, vp9: true, aac: true, ac3: false, eac3: false,
    opus: true, flac: true, ...overrides
  };
  return load('lib/streamCompatibility.ts', {
    './capabilities': { getMediaCapabilities: () => caps },
    './debrid': debrid
  }, { navigator: userAgent === null ? undefined : { userAgent } });
}

function stream(overrides = {}) {
  return { url: 'https://media.invalid/Film.mp4', source: 'Fixture', description: '', ...overrides };
}

function assertPlan(module, source, mode, route, method) {
  assert.equal(module.streamPlayability(source).mode, mode);
  const plan = module.playbackPlan(source);
  assert.equal(plan.route, route);
  assert.equal(plan.method, method);
  assert.equal(module.isBrowserPlayableStream(source), route === 'here');
  assert.equal(module.isDirectPlayableStream(source), mode === 'direct');
  assert.equal(module.playbackWarning(source), plan.detail);
}

for (const resolution of ['2160p', '4K', 'UHD']) {
  test(`${resolution} AV1 uses the AV1 decoder, never an inferred HEVC decoder`, () => {
    const source = stream({ description: `Film.${resolution}.AV1.AAC` });
    const playable = compatibility({ av1: true, hevc: false, hevc10: false });
    assert.equal(playable.videoDecodableForDevice(source), true);
    assertPlan(playable, source, 'direct', 'here', 'direct');
    const blocked = compatibility({ av1: false, hevc: true, hevc10: true });
    assert.equal(blocked.videoDecodableForDevice(source), false);
    assertPlan(blocked, source, 'external', 'vlc', 'direct');
    assert.match(blocked.playbackPlan(source).detail, /AV1/);
    assert.doesNotMatch(blocked.playbackPlan(source).detail, /HEVC/);
  });
}

test('Resolution alone is not a codec, and measured codec metadata wins over release text', () => {
  const module = compatibility();
  for (const description of ['Film.2160p', 'Film.4K', 'Film.UHD']) {
    assertPlan(module, stream({ description }), 'direct', 'here', 'direct');
  }
  assertPlan(module, stream({
    description: 'Film.4K.HEVC.DTS',
    media: { container: 'mp4', videoCodec: 'av01.0.08M.08', audioCodec: 'aac' }
  }), 'direct', 'here', 'direct');
  const hevc = stream({ description: 'Film.AV1', media: { videoCodec: 'hevc' } });
  assert.equal(module.videoDecodableForDevice(hevc), false);
  assertPlan(module, hevc, 'external', 'vlc', 'direct');
});

test('Extensionless and proxied URLs use the MKV filename hint for routing', () => {
  const url = 'https://media.invalid/download/123?token=fixture';
  const sources = [url, `https://proxy.invalid/api/proxy?url=${encodeURIComponent(url)}`].map((url) => stream({
    url, behaviorHints: { filename: 'Film.2160p.AV1.AAC.MKV' }
  }));
  for (const source of sources) {
    const module = compatibility();
    assert.equal(module.streamContainer(source), 'mkv');
    assert.equal(module.streamTransport(source), 'file');
    assertPlan(module, source, 'remux', 'here', 'remux');
    assertPlan(compatibility({}, CHROME), source, 'direct', 'here', 'direct');
  }
});

test('Explicit container metadata wins over filename and URL container hints', () => {
  const module = compatibility();
  const source = stream({
    url: 'https://media.invalid/film.mkv',
    behaviorHints: { filename: 'Film.mkv' },
    media: { container: 'MP4', videoCodec: 'h264', audioCodec: 'aac' }
  });
  assert.equal(module.streamContainer(source), 'mp4');
  assertPlan(module, source, 'direct', 'here', 'direct');
});

for (const [browser, userAgent] of [
  ['iPhone Chrome', 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 CriOS/145.0.0.0 Mobile/15E148 Safari/604.1'],
  ['iPad Chrome', 'Mozilla/5.0 (iPad; CPU OS 19_0 like Mac OS X) AppleWebKit/605.1.15 CriOS/145.0.0.0 Mobile/15E148 Safari/604.1'],
  ['iOS Edge with a Chrome token', 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 Chrome/145.0.0.0 EdgiOS/145.0 Mobile/15E148 Safari/604.1'],
  ['iOS Firefox with a Chrome token', 'Mozilla/5.0 AppleWebKit/605.1.15 Chrome/145.0.0.0 FxiOS/145.0 Mobile/15E148 Safari/604.1']
]) {
  test(`${browser} never receives the desktop Chromium direct-MKV route`, () => {
    const source = stream({ url: 'https://media.invalid/Film.mkv', description: 'Film.H264.AAC' });
    const module = compatibility({}, userAgent);
    assert.equal(module.canDirectPlayMkvStream(source), false);
    assert.equal(module.isIosPlayableStream(source), false);
    assertPlan(module, source, 'remux', 'here', 'remux');
    assertPlan(compatibility({ mse: false }, userAgent), source, 'external', 'vlc', 'direct');
  });
}

test('Desktop Chromium direct-MKV routing requires the supported version and codecs', () => {
  const source = stream({ url: 'https://media.invalid/Film.mkv', media: { videoCodec: 'h264', audioCodec: 'aac' } });
  for (const userAgent of [CHROME, CHROME.replace('Chrome/', 'Chromium/'), CHROME.replace('Chrome/', 'Edg/')]) {
    assert.equal(compatibility({}, userAgent).canDirectPlayMkvStream(source), true);
  }
  for (const userAgent of [CHROME.replace('145.', '144.'), FIREFOX, null]) {
    assert.equal(compatibility({}, userAgent).canDirectPlayMkvStream(source), false);
    assertPlan(compatibility({}, userAgent), source, 'remux', 'here', 'remux');
  }
  assertPlan(compatibility({}, CHROME), { ...source, media: { videoCodec: 'hevc', audioCodec: 'aac' } }, 'external', 'vlc', 'direct');
});

for (const audioCodec of ['ac3', 'eac3', 'ec-3', 'dts', 'dca']) {
  test(`${audioCodec} audio uses browser remux when MSE is available, including Chromium MKV`, () => {
    for (const container of ['mp4', 'mkv']) {
      const source = stream({ url: `https://media.invalid/Film.${container}`, media: { videoCodec: 'h264', audioCodec } });
      for (const userAgent of [FIREFOX, CHROME]) {
        const module = compatibility({}, userAgent);
        assert.equal(module.audioDecodableForDevice(source), true);
        assert.equal(module.canDirectPlayMkvStream(source), false);
        assertPlan(module, source, 'remux', 'here', 'remux');
        const noMse = compatibility({ mse: false }, userAgent);
        assert.equal(noMse.audioDecodableForDevice(source), false);
        assertPlan(noMse, source, 'external', 'vlc', 'direct');
      }
    }
  });
}

test('Supported Dolby audio stays direct in MP4 and on supported Chromium MKV', () => {
  for (const audioCodec of ['ac3', 'eac3']) {
    for (const container of ['mp4', 'mkv']) {
      const source = stream({ url: `https://media.invalid/Film.${container}`, media: { videoCodec: 'h264', audioCodec } });
      assertPlan(compatibility({ ac3: true, eac3: true }, CHROME), source, 'direct', 'here', 'direct');
    }
  }
});

test('TrueHD and MLP metadata never become decodable through a case-sensitive MSE fallback', () => {
  for (const mse of [false, true]) {
    const module = compatibility({ mse });
    for (const audioCodec of ['truehd', 'TrueHD', 'TRUEHD', 'True-HD', 'True HD', 'mlp', 'MLP']) {
      const source = stream({ media: { videoCodec: 'h264', audioCodec } });
      assert.equal(module.audioDecodableForDevice(source), false, `${audioCodec}, mse=${mse}`);
    }
    assert.equal(module.audioDecodableForDevice(stream({ media: { audioCodec: 'AAC' } })), true);
  }
});

for (const [extension, transport] of [['m3u8', 'hls'], ['mpd', 'dash'], ['ts', 'mpegts']]) {
  test(`${transport} with known unsupported audio does not advertise direct playback`, () => {
    for (const mse of [false, true]) {
      const source = stream({
        url: `https://media.invalid/live.${extension}`,
        media: { videoCodec: 'h264', audioCodec: 'EAC3' }
      });
      const module = compatibility({ mse, nativeHls: true, eac3: false });
      assert.equal(module.streamTransport(source), transport);
      assert.equal(module.canTryRemux(source), false);
      assertPlan(module, source, 'external', 'vlc', 'direct');
      assert.match(module.playbackPlan(source).detail, /audio conversion/i);
      assertPlan(module, { ...source, url: 'https://media.invalid/live', transport }, 'external', 'vlc', 'direct');
      assertPlan(module, { ...source, homeServer: { serverId: 'fixture', itemId: 'live' } }, 'transcode', 'here', 'transcode');
      assertPlan(compatibility({ mse, nativeHls: true, eac3: true }), source, 'direct', 'here', 'direct');
    }
  });
}

for (const provider of ['premiumize', 'alldebrid', 'torbox', 'realdebrid']) {
  test(`${provider} conversion claims match the supported provider routes`, () => {
    const source = stream({
      url: `https://resolver.invalid/resolve/${provider}/fixture-key/${'a'.repeat(40)}/0/Film.mkv`,
      media: { videoCodec: 'hevc', audioCodec: 'aac' }
    });
    const module = compatibility();
    const canTranscode = provider === 'torbox' || provider === 'realdebrid';
    assert.equal(debrid.parseDebridStream(source.url).provider, provider);
    assert.equal(module.canProviderTranscode(source), canTranscode);
    assert.equal(module.canProviderTranscode({ ...source, originalUrl: source.url, url: 'https://cdn.invalid/selected.mkv' }), canTranscode);
    assertPlan(module, source, canTranscode ? 'transcode' : 'external', canTranscode ? 'here' : 'vlc', canTranscode ? 'transcode' : 'direct');
    if (!canTranscode) assert.doesNotMatch(module.playbackPlan(source).detail, /converted|transcod|server conversion/i);
    const playable = { ...source, media: { videoCodec: 'h264', audioCodec: 'eac3' } };
    assertPlan(module, playable, 'remux', 'here', 'remux');
    assertPlan(compatibility({ mse: false }), playable, canTranscode ? 'transcode' : 'external', canTranscode ? 'here' : 'vlc', canTranscode ? 'transcode' : 'direct');
  });
}

test('Home-server conversion remains available without implying debrid conversion', () => {
  const source = stream({ homeServer: { type: 'jellyfin', serverId: 'fixture' }, media: { videoCodec: 'hevc' } });
  assertPlan(compatibility(), source, 'transcode', 'here', 'transcode');
});

test('Unresolved and non-media sources stay locked', () => {
  const module = compatibility();
  for (const source of [
    stream({ url: undefined }),
    stream({ behaviorHints: { notWebReady: true } }),
    stream({ url: 'https://media.invalid/Film.mkv.zip' })
  ]) assertPlan(module, source, 'locked', 'dead', 'direct');
});

test('HLS, DASH and MPEG-TS transports are not sent to file remux', () => {
  const module = compatibility();
  for (const [path, transport] of [
    ['/live/1.m3u8', 'hls'], ['/live/1.mpd', 'dash'], ['/live/1.ts', 'mpegts'], ['/live/user/pass/1', 'mpegts']
  ]) {
    const source = stream({ url: `https://media.invalid${path}?token=fixture` });
    assert.equal(module.streamTransport(source), transport);
    assert.equal(module.canTryRemux(source), false);
    assertPlan(module, source, 'direct', 'here', 'direct');
  }
});
