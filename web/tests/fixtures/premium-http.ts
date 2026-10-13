export class HttpError extends Error { constructor(public status: number, message: string) { super(message); } }
const trial = { entitled: true, reason: 'trial', status: 'active', source: 'trial', expiresAt: new Date(Date.now() + 86400000).toISOString(), trialAvailable: false, trialDurationDays: 3 };
const paid = { ...trial, reason: 'subscription', source: 'kofi' };
let state = new URLSearchParams(location.search).get('case') === 'paywall' ? { ...trial, entitled: false, reason: 'none', trialAvailable: true } : trial;
let checkoutSeen = false;
let paymentChecks = 0;
export async function jsonRequest(url: string, init: RequestInit = {}) {
  const body = init.body ? JSON.parse(String(init.body)) : {};
  if (url.endsWith('/premium-funnel-event')) { if (body.event_name === 'checkout_opened') checkoutSeen = true; return { ok: true }; }
  if (url.endsWith('/entitlement-link')) {
    if (!body.code) return { verificationRequired: true };
    if (body.code !== '1234567890abcdef') throw new HttpError(400, 'Invalid or expired verification code.');
    state = paid;
    return state;
  }
  if (url.endsWith('/entitlement-status')) {
    if (new URLSearchParams(location.search).get('case') === 'error') throw new HttpError(503, 'Fixture outage');
    if (init.method === 'POST') state = trial;
    if (checkoutSeen && new URLSearchParams(location.search).get('case') === 'delayed-payment' && ++paymentChecks >= 2) state = paid;
    return state;
  }
  throw Error('Unmocked request blocked');
}
