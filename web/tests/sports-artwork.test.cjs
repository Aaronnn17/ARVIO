const test = require('node:test');
const assert = require('node:assert/strict');
const ts = require('typescript');
const fs = require('node:fs');
const vm = require('node:vm');
const transpile = path => ts.transpileModule(fs.readFileSync(require.resolve(path), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
const guide = { exports: {} }; vm.runInNewContext(transpile('../lib/sportsGuide.ts'), guide);
let requests = 0;
const meta = { id: 'event:1', name: 'Barcelona vs Feyenoord', genres: ['Football'], background: 'https://example.com/event.webp', poster: 'https://example.com/event_UTC.webp' };
const sandbox = { exports: {}, URL, Date, setTimeout, clearTimeout, AbortController,
  require: name => name === './sportsGuide' ? guide.exports : { proxiedUrl: url => url, jsonRequest: async () => { requests++; return { metas: [meta] }; } } };
vm.runInNewContext(transpile('../lib/sportsArtwork.ts'), sandbox);
const { sportsArtworkKey, toSportsEventArtwork, attachSportsArtwork, loadSportsGuideArtwork } = sandbox.exports;
const event = { id: 'epg', title: 'LIVE: Football: Barcelona vs. Feyenoord', sportId: 'football', programme: { startUtcMillis: 1, endUtcMillis: 2 }, channels: [] };
test('untimed event background wins; no foreign timezone poster or channel cover', () => {
  assert.equal(toSportsEventArtwork(meta).background, meta.background);
  for (const value of [{...meta, background: null}, {...meta, background: meta.poster}, {...meta, id: 'leaf:channel'}, {...meta, background: 'file:///private'}, null]) assert.equal(toSportsEventArtwork(value), null);
});
test('exact normalized event match preserves programme facts', () => {
  const actual = attachSportsArtwork([event], [toSportsEventArtwork(meta)])[0];
  assert.equal(actual.artwork, meta.background);
  assert.equal(actual.programme, event.programme);
  assert.equal(actual.channels, event.channels);
  assert.equal(sportsArtworkKey('São Paulo versus Feyenoord'), sportsArtworkKey('Sao Paulo vs. Feyenoord'));
});
test('different teams/sport cannot borrow a matching-looking banner', () => {
  for (const changed of [{...event, title: 'Barcelona vs Madrid'}, {...event, sportId: 'basketball'}]) assert.equal(attachSportsArtwork([changed], [toSportsEventArtwork(meta)])[0].artwork, undefined);
});
test('removing artwork clears the banner', () => assert.equal(attachSportsArtwork([{...event, artwork: meta.background}], [])[0].artwork, undefined));
test('EPG dash separators match without mixing different teams or youth/womens fixtures', () => {
  for (const title of ['Barcelona - Feyenoord', 'Football: Barcelona – Feyenoord', 'Feyenoord at Barcelona']) {
    assert.equal(attachSportsArtwork([{...event, title}], [toSportsEventArtwork(meta)])[0].artwork, meta.background);
  }
  for (const title of ['Barcelona U21 - Feyenoord U21', 'Barcelona Women - Feyenoord Women', 'Barcelona - Madrid']) {
    assert.equal(attachSportsArtwork([{...event, title}], [toSportsEventArtwork(meta)])[0].artwork, undefined);
  }
});
test('catalog requests are bounded and concurrent callers share cached work', async () => {
  const addon = { id: 'sports', enabled: true, manifestUrl: 'https://example.com/manifest.json', resources: ['stream'], catalogs: Array.from({length:20}, (_,i) => ({id:`sports_${i}`, type:'sport', name:`Sports ${i}`})) };
  const addons = [addon, {...addon, id:'second', manifestUrl:'https://two.example/manifest.json'}, {...addon, id:'third'}];
  await Promise.all([loadSportsGuideArtwork(addons), loadSportsGuideArtwork(addons)]);
  assert.equal(requests, 6);
  await loadSportsGuideArtwork(addons);
  assert.equal(requests, 6);
  await loadSportsGuideArtwork([{...addon, enabled: false}]);
  assert.equal(requests, 6);
});
