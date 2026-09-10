const test = require('node:test');
const assert = require('node:assert/strict');
const ts = require('typescript');
const fs = require('node:fs');
const vm = require('node:vm');
const modules = {};
function load(name) {
  if (modules[name]) return modules[name];
  if (name === './http') return {};
  if (name === './config') return { config: {} };
  const sandbox = { exports: {}, URL, Date, require: load };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(`${__dirname}/../lib/${name.slice(2)}.ts`, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText, sandbox);
  return modules[name] = sandbox.exports;
}
const { parseSportsMetadata } = load('./sportsArtwork');
const { buildSportsCatalogue, sportsProminence } = load('./sportsCatalogue');
const { sportsGuideRows, isOnAir, isConfirmedLive, availableEventChannels, hasSportsChannels } = load('./sportsGuide');
const now = Date.parse('2026-09-10T12:00:00Z');
const channel = { id: 'p:1', name: 'UK | Sky Sports Main Event FHD', streamUrl: 'https://example.invalid/live' };
const raw = { id: '42', title: 'North vs South', sport: 'Soccer', startsAt: now + 3600000, status: 'scheduled', league: 'English Premier League', observedAt: now,
  broadcasters: [{ name: 'Sky Sports Main Event HD', country: 'United Kingdom', startsAt: now + 3600000 }] };
const art = (changes = {}) => parseSportsMetadata({ version: 1, catalogueEnabled: true, events: [{ ...raw, ...changes }] });
const epg = { id: 'guide', title: raw.title, sportId: 'football', competition: 'Premier League', programme: { title: raw.title, startUtcMillis: now - 60000, endUtcMillis: now + 3600000 }, channels: [channel], schedules: { [channel.id]: { title: raw.title, startUtcMillis: now - 60000, endUtcMillis: now + 3600000 } } };

test('fixtures without pictures or guide remain browsable, no invented duration or live flag', () => {
  const event = buildSportsCatalogue([], art(), [], now)[0];
  assert.equal(event.id, 'sportsdb:42');
  assert.equal(event.channels.length, 0);
  assert.equal(hasSportsChannels(event, now), false);
  assert.equal(isOnAir(event, now), false);
  assert.equal(isOnAir(event, now + 7200000), false);
  assert.equal(sportsGuideRows([event], now)[0].id, 'upcoming');
});
test('channel hints are separate from confirmed guide matches and respect regional prefixes', () => {
  const hint = buildSportsCatalogue([], art(), [channel, { ...channel, id: 'wrong-country', name: 'DE | Sky Sports Main Event HD' }], now)[0];
  assert.equal(hint.channels.length, 0);
  assert.equal(hint.possibleChannels.length, 1);
  assert.equal(hasSportsChannels(hint, now), true);
  const actual = buildSportsCatalogue([epg], art({ startsAt: now }), [channel], now);
  assert.equal(actual.length, 1);
  assert.equal(availableEventChannels(actual[0], now).length, 1);
  assert.equal(actual[0].schedules[channel.id].endUtcMillis, epg.programme.endUtcMillis);
  assert.equal(buildSportsCatalogue([], art(), [], now)[0].possibleChannels.length, 0);
});
test('50k channel index and 2k fixtures remain bounded without stream requests', () => {
  const channels = Array.from({length: 50000}, (_, i) => ({...channel, id: `p:${i}`, name: `Channel ${i}`}));
  const metadata = parseSportsMetadata({ version: 1, catalogueEnabled: true, events: Array.from({length: 2000}, (_, i) => ({...raw, id: String(i + 1), title: `Team ${i} vs Other`, broadcasters: [{name: `Channel ${i}`, country: '', startsAt: raw.startsAt}]})) });
  const start = performance.now();
  const events = buildSportsCatalogue([], metadata, channels, now);
  const elapsed = performance.now() - start;
  assert.equal(events.length, 2000);
  assert.equal(events.filter(e => e.possibleChannels.length === 1).length, 2000);
  console.log(`50k channels / 2k fixtures indexed in ${Math.round(elapsed)}ms (host JS, not a device frame benchmark)`);
  assert.ok(elapsed < 5000);
});
test('women, other sports, other leagues and distant broadcasts cannot steal matches', () => {
  for (const changes of [{ qualifier: 'women' }, { sport: 'Basketball' }, { startsAt: now + 10800000 }, { league: 'UEFA Champions League' }]) {
    const result = buildSportsCatalogue([epg], art(changes), [], now);
    assert.equal(result.find(e => e.fixture).channels.length, 0);
    assert.equal(result.filter(e => !e.fixture).length, 1);
  }
});
test('live scores expire independently; finished status suppresses stale guide', () => {
  const event = buildSportsCatalogue([], art({ startsAt: now - 60000, status: 'live' }), [], now)[0];
  assert.equal(isConfirmedLive(event, now), true);
  assert.equal(isOnAir(event, now + 300001), false);
  assert.equal(buildSportsCatalogue([epg], art({ startsAt: now, status: 'finished' }), [], now).length, 0);
});
test('featured live ranks prominent competitions first; upcoming remains chronological', () => {
  const prominent = buildSportsCatalogue([], art({ startsAt: now - 60000, status: 'live' }), [], now)[0];
  const minor = { ...prominent, id: 'minor', prominence: sportsProminence('Minor League') };
  assert.equal(sportsGuideRows([minor, prominent], now)[0].events[0].id, prominent.id);
  const later = { ...prominent, id: 'later', fixture: { ...prominent.fixture, status: 'scheduled' }, programme: { ...prominent.programme, startUtcMillis: now + 7200000 } };
  const earlier = { ...later, id: 'earlier', prominence: 0, programme: { ...later.programme, startUtcMillis: now + 3600000 } };
  assert.equal(sportsGuideRows([later, earlier], now)[0].events[0].id, 'earlier');
});
test('backend kill switch retains legacy artwork mode', () => {
  const items = parseSportsMetadata({ version: 1, catalogueEnabled: false, events: [raw] });
  assert.equal(items.length, 0);
});
