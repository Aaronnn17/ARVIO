const DAY = 86_400_000;
const CACHE_KEY = 'fixtures-v2';
const REFRESH_MS = 30 * 60_000;
const RETRY_MS = 5 * 60_000;
const MAX_AGE = 24 * 60 * 60_000;

function image(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && ['www.thesportsdb.com', 'r2.thesportsdb.com'].includes(url.hostname)
      && url.pathname.startsWith('/images/media/') && !url.search && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

function normalizeEvent(event) {
  if (!event || typeof event !== 'object' || !/^\d+$/.test(event.idEvent)) return null;
  const title = typeof event.strEvent === 'string' ? event.strEvent.trim().slice(0, 240) : '';
  const rawSport = typeof event.strSport === 'string' ? event.strSport.trim().slice(0, 80) : '';
  // Some feeds omit women/youth qualifiers from team titles. Do not let those
  // banners match an unqualified men's programme simply because names coincide.
  const qualifier = /women|womens|women's|youth|u\d{2}\b|under[ -]?\d{2}/i;
  const leagueQualifier = String(event.strLeague || '').match(qualifier)?.[0];
  if (leagueQualifier && !qualifier.test(title)) return null;
  const sport = rawSport === 'Fighting' && /ufc|mma|mixed martial/i.test(event.strLeague || '') ? 'MMA'
    : rawSport === 'Motorsport' && /formula 1|formula one/i.test(event.strLeague || '') ? 'Formula 1' : rawSport;
  // SportsDB timestamps without an offset are UTC, never the server's local time.
  const timestamp = event.strTimestamp || (event.dateEvent && event.strTime ? `${event.dateEvent}T${event.strTime}` : '');
  const startsAt = typeof timestamp === 'string' && timestamp.includes('T')
    ? Date.parse(/[zZ]|[+-]\d{2}:?\d{2}$/.test(timestamp) ? timestamp : `${timestamp}Z`) : NaN;
  if (!title || !sport || !Number.isFinite(startsAt) || /postponed|cancelled|canceled|abandoned/i.test(event.strStatus || '') || event.strPostponed === 'yes') return null;
  const background = image(event.strThumb) || image(event.strFanart);
  const homeBadge = image(event.strHomeTeamBadge), awayBadge = image(event.strAwayTeamBadge);
  const teamPair = event.idHomeTeam && event.idAwayTeam && event.idHomeTeam !== event.idAwayTeam
    && event.strHomeTeam && event.strAwayTeam && homeBadge && awayBadge;
  if (!background && !teamPair) return null;
  return {
    id: String(event.idEvent), title, sport, startsAt, background,
    homeBadge: teamPair ? homeBadge : null, awayBadge: teamPair ? awayBadge : null,
    homeTeam: teamPair ? String(event.strHomeTeam).slice(0, 120) : null,
    awayTeam: teamPair ? String(event.strAwayTeam).slice(0, 120) : null,
    league: typeof event.strLeague === 'string' ? event.strLeague.slice(0, 120) : null,
  };
}

async function fetchFixtures({ fetcher, apiKey, now }) {
  const events = new Map();
  let partial = false;
  // Fixed shared window, not client-controlled upstream queries. Covers local today/tomorrow in every timezone.
  for (const offset of [-1, 0, 1, 2]) {
    const day = new Date(now + offset * DAY).toISOString().slice(0, 10);
    const response = await fetcher(`https://www.thesportsdb.com/api/v1/json/${encodeURIComponent(apiKey)}/eventsday.php?d=${day}`, {
      signal: AbortSignal.timeout(4_000), redirect: 'error', headers: { Accept: 'application/json' },
    });
    if (!response.ok) throw new Error('Sports metadata unavailable');
    const payload = await response.json();
    if (!payload || !Object.prototype.hasOwnProperty.call(payload, 'events') || (payload.events !== null && !Array.isArray(payload.events))) throw new Error('Invalid sports metadata');
    const rows = payload.events || [];
    partial ||= rows.length >= 1500;
    for (const row of rows.slice(0, 1500)) {
      const event = normalizeEvent(row);
      if (event) events.set(event.id, event);
    }
  }
  return { version: 1, updatedAt: now, partial, attribution: 'TheSportsDB', events: [...events.values()] };
}

// The shared record doubles as a CAS lease. A failed refresh backs off across ALL instances,
// not just one warm function. Never fall back to uncoordinated upstream requests on cache errors.
async function getMetadata({ store, apiKey, fetcher = fetch, now = Date.now(), report = () => {} }) {
  const record = await store.getWithMetadata(CACHE_KEY, { type: 'json', consistency: 'strong' });
  const cached = record?.data?.payload;
  const usable = cached?.version === 1 && now - cached.updatedAt < MAX_AGE ? cached : null;
  if (record?.data?.refreshAfter > now) { report('backoff'); return usable; }
  if (!apiKey) { report('not-configured'); return usable; }
  if (record && !record.etag) return usable;
  const claim = await store.setJSON(CACHE_KEY, { payload: usable, refreshAfter: now + RETRY_MS },
    record ? { onlyIfMatch: record.etag } : { onlyIfNew: true });
  if (!claim.modified || !claim.etag) return usable;
  try {
    const payload = await fetchFixtures({ fetcher, apiKey, now });
    await store.setJSON(CACHE_KEY, { payload, refreshAfter: now + REFRESH_MS }, { onlyIfMatch: claim.etag });
    return payload;
  } catch {
    // Do not log upstream URLs or errors: V1 embeds the secret in its URL.
    report('upstream-unavailable');
    return usable;
  }
}

const headers = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET,OPTIONS',
  'x-content-type-options': 'nosniff',
};
function createHandler(dependencies) {
  return async event => {
    if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
    if (event.httpMethod !== 'GET') return { statusCode: 405, headers: { ...headers, allow: 'GET,OPTIONS' }, body: '{}' };
    let state = 'refreshing';
    try {
      const payload = await getMetadata({ ...await dependencies(event), report: value => { state = value; } });
      if (payload) return { statusCode: 200, headers: { ...headers, 'cache-control': 'public, max-age=60, s-maxage=300' }, body: JSON.stringify(payload) };
    } catch { state = 'cache-unavailable'; }
    return { statusCode: 503, headers: { ...headers, 'cache-control': 'no-store', 'retry-after': '60', 'x-artwork-status': state }, body: '{"error":"Sports artwork is temporarily unavailable"}' };
  };
}
module.exports = { normalizeEvent, fetchFixtures, getMetadata, createHandler };
