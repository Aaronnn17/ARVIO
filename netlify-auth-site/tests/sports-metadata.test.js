const { test } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeEvent, getMetadata, createHandler } = require('../netlify/functions/_sports-metadata');
const now = Date.parse('2026-09-10T12:00:00Z');
const badge = 'https://r2.thesportsdb.com/images/media/team/badge/test.png';
const fixture = { idEvent: '123', strEvent: 'Alpha vs Beta', strSport: 'Soccer', strTimestamp: '2026-09-10T14:00:00', idHomeTeam: '1', idAwayTeam: '2', strHomeTeam: 'Alpha', strAwayTeam: 'Beta', strHomeTeamBadge: badge, strAwayTeamBadge: badge };
function store() {
  let value = null, revision = 0;
  return {
    getWithMetadata: async () => value && { data: structuredClone(value), etag: String(revision) },
    setJSON: async (_, data, options) => {
      if ((options.onlyIfNew && value) || (options.onlyIfMatch !== undefined && options.onlyIfMatch !== String(revision))) return { modified: false };
      value = structuredClone(data); return { modified: true, etag: String(++revision) };
    },
  };
}
test('UTC fixtures, verified pairs, and only public artwork fields', () => {
  const event = normalizeEvent({ ...fixture, secret: 'must-not-escape' });
  assert.equal(event.startsAt, Date.parse('2026-09-10T14:00:00Z'));
  assert.equal(event.homeBadge, badge);
  assert.equal(event.secret, undefined);
  assert.equal(normalizeEvent({ ...fixture, strAwayTeamBadge: 'https://evil.test/art.png' }), null);
  assert.equal(normalizeEvent({ ...fixture, strStatus: 'Postponed' }), null);
  assert.equal(normalizeEvent({ ...fixture, strLeague: 'Women\'s Champions League' }), null);
  assert.equal(normalizeEvent({ ...fixture, strLeague: 'Youth League' }), null);
  assert.equal(normalizeEvent({ ...fixture, strTimestamp: '', dateEvent: '2026-09-10' }), null);
  assert.equal(normalizeEvent({ ...fixture, strThumb: 'https://r2.thesportsdb.com/images/media/event/thumb/a.jpg' }).background.endsWith('a.jpg'), true);
});
test('100 concurrent clients consume FOUR upstream requests, then reuse shared cache', async () => {
  let calls = 0;
  const shared = store();
  const deps = { store: shared, apiKey: 'test-only-key', now, fetcher: async () => { calls++; return { ok: true, json: async () => ({ events: [fixture] }) }; } };
  await Promise.all(Array.from({ length: 100 }, () => getMetadata(deps)));
  assert.equal(calls, 4);
  const result = await getMetadata({ ...deps, now: now + 60_000 });
  assert.equal(result.events.length, 1);
  assert.equal(calls, 4);
});
test('refresh failure serves stale artwork and globally backs off; no secret in response', async () => {
  const shared = store(); let calls = 0;
  const deps = { store: shared, apiKey: 'secret-key', now, fetcher: async () => ({ ok: true, json: async () => ({ events: [fixture] }) }) };
  const old = await getMetadata(deps);
  const failed = { ...deps, now: now + 31 * 60_000, fetcher: async () => { calls++; throw new Error('https://api/secret-key'); } };
  assert.deepEqual(await getMetadata(failed), old);
  assert.deepEqual(await getMetadata(failed), old);
  assert.equal(calls, 1);
  const handler = createHandler(() => ({ ...failed, store: store() }));
  const response = await handler({ httpMethod: 'GET' });
  assert.equal(response.statusCode, 503);
  assert.ok(!JSON.stringify(response).includes('secret-key'));
  assert.equal((await handler({ httpMethod: 'POST' })).statusCode, 405);
});
test('cache failure and missing API key never fall back to direct traffic', async () => {
  let calls = 0;
  const fetcher = async () => { calls++; throw new Error(); };
  assert.equal(await getMetadata({ store: store(), fetcher, now }), null);
  const handler = createHandler(() => ({ store: { getWithMetadata: async () => { throw new Error(); } }, apiKey: 'key', fetcher, now }));
  assert.equal((await handler({ httpMethod: 'GET' })).statusCode, 503);
  assert.equal(calls, 0);
});
