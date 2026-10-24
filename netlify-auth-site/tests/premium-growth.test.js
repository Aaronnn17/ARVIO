const test = require('node:test');
const assert = require('node:assert/strict');

// In-memory Netlify Blobs with the parts of the API these modules use.
const stores = new Map();
function memoryStore() {
  const data = new Map();
  let version = 0;
  const etags = new Map();
  const clone = (value) => (value === undefined ? undefined : structuredClone(value));
  return {
    data,
    async get(key) { return data.has(key) ? clone(data.get(key)) : null; },
    async getWithMetadata(key) { return data.has(key) ? { data: clone(data.get(key)), etag: etags.get(key) } : null; },
    async setJSON(key, value, opts = {}) {
      if (opts.onlyIfNew && data.has(key)) return { modified: false };
      if (opts.onlyIfMatch && etags.get(key) !== opts.onlyIfMatch) return { modified: false };
      data.set(key, clone(value)); etags.set(key, `e${++version}`);
      return { modified: true };
    },
    async delete(key) { data.delete(key); etags.delete(key); },
    async list({ prefix = '' } = {}) { return { blobs: [...data.keys()].filter((k) => k.startsWith(prefix)).map((key) => ({ key })) }; }
  };
}
function store(name) { if (!stores.has(name)) stores.set(name, memoryStore()); return stores.get(name); }
require.cache[require.resolve('@netlify/blobs')] = { id: '@netlify/blobs', filename: '@netlify/blobs', loaded: true, exports: { connectLambda() {}, getStore: (name) => store(name) } };

process.env.ARVIO_AUTH_SECRET = 'x'.repeat(40);
process.env.KOFI_VERIFICATION_TOKEN = 'kofi-token';
process.env.KOFI_YEARLY_ITEM_CODES = 'abc123def, other999';
process.env.KOFI_YEARLY_URL = 'https://ko-fi.com/s/abc123def';
process.env.STREAM_TICKET_SECRET = 's'.repeat(40);

const { evaluateEntitlement, buildPaidRecord, DAY_MS } = require('../netlify/functions/_entitlements');
const webhook = require('../netlify/functions/kofi-webhook');
const referrals = require('../netlify/functions/_referrals');
const memberEmails = require('../netlify/functions/_member-emails');
const streamTicket = require('../netlify/functions/stream-ticket');
const exitSurvey = require('../netlify/functions/premium-exit-survey');
const { sha256 } = require('../netlify/functions/_backend');

const NOW = Date.parse('2026-11-01T12:00:00Z');
const reset = () => stores.clear();
const entitlement = (email) => store('entitlements').data.get(`email/${sha256(email)}.json`);
const kofi = (data) => webhook.handler({ httpMethod: 'POST', body: new URLSearchParams({ data: JSON.stringify({ verification_token: 'kofi-token', ...data }) }).toString() });

test('paid time stacks on time still ahead and never throws days away', () => {
  const active = { status: 'active', source: 'kofi', startedAt: '2026-10-01T00:00:00Z', expiresAt: new Date(NOW + 10 * DAY_MS).toISOString() };
  assert.equal(buildPaidRecord(active, { days: 31, now: NOW }).expiresAt, new Date(NOW + 41 * DAY_MS).toISOString());
  const lapsed = { ...active, expiresAt: new Date(NOW - 5 * DAY_MS).toISOString() };
  assert.equal(buildPaidRecord(lapsed, { days: 31, now: NOW }).expiresAt, new Date(NOW + 31 * DAY_MS).toISOString());
  assert.equal(buildPaidRecord({ ...active, expiresAt: null }, { days: 31, now: NOW }).expiresAt, null, 'lifetime stays lifetime');
  const trial = { status: 'active', source: 'trial', expiresAt: new Date(NOW + 2 * DAY_MS).toISOString(), startedAt: '2026-10-30T00:00:00Z' };
  const upgraded = buildPaidRecord(trial, { days: 31, now: NOW });
  assert.equal(upgraded.expiresAt, new Date(NOW + 31 * DAY_MS).toISOString(), 'a legacy trial deadline is not paid time');
  assert.equal(upgraded.startedAt, new Date(NOW).toISOString());
});

test('a late renewal keeps access for 3 days of grace, then access ends', () => {
  const record = (daysAgo) => ({ status: 'active', source: 'kofi', startedAt: '2026-09-01T00:00:00Z', expiresAt: new Date(NOW - daysAgo * DAY_MS).toISOString() });
  const grace = evaluateEntitlement(record(1), NOW);
  assert.equal(grace.entitled, true);
  assert.equal(grace.reason, 'grace');
  assert.equal(grace.graceEndsAt, new Date(NOW + 2 * DAY_MS).toISOString());
  assert.equal(evaluateEntitlement(record(4), NOW).entitled, false);
  assert.equal(evaluateEntitlement(record(4), NOW).everPaid, true);
  assert.equal(evaluateEntitlement({ status: 'active', source: 'trial', expiresAt: new Date(NOW - DAY_MS).toISOString() }, NOW).entitled, false, 'legacy trials get no grace');
  assert.equal(evaluateEntitlement({ status: 'cancelled', source: 'kofi', expiresAt: new Date(NOW - DAY_MS).toISOString() }, NOW).entitled, false, 'revoked access gets no grace');
});

test('monthly payments: first payment queues the first-month emails, retries never grant twice', async () => {
  reset();
  const first = await kofi({ type: 'Subscription', email: 'Member@Example.test', is_subscription_payment: true, is_first_subscription_payment: true, kofi_transaction_id: 'tx-1', tier_name: 'Premium' });
  assert.equal(first.statusCode, 200);
  assert.equal(first.body ? JSON.parse(first.body).plan : null, 'monthly');
  const record = entitlement('member@example.test');
  assert.equal(record.plan, 'monthly');
  assert.deepEqual(record.payments, ['tx-1']);
  const jobs = [...store('premium-member-emails').data.values()].map((job) => job.type).sort();
  assert.deepEqual(jobs, ['tips_day7', 'yearly_day20']);
  assert.ok(![...store('premium-member-emails').data.values()].some((job) => JSON.stringify(job).includes('member@example.test')), 'addresses are stored encrypted');

  const retry = await kofi({ type: 'Subscription', email: 'member@example.test', is_subscription_payment: true, kofi_transaction_id: 'tx-1' });
  assert.equal(JSON.parse(retry.body).duplicate, true);
  assert.equal(entitlement('member@example.test').expiresAt, record.expiresAt);

  await kofi({ type: 'Subscription', email: 'member@example.test', is_subscription_payment: true, kofi_transaction_id: 'tx-2' });
  assert.equal(Date.parse(entitlement('member@example.test').expiresAt) - Date.parse(record.expiresAt), 31 * DAY_MS, 'an early renewal adds on top');
});

test('a 12-month pass grants 366 days, stacks on a membership and schedules two reminders', async () => {
  reset();
  await kofi({ type: 'Subscription', email: 'pass@example.test', is_subscription_payment: true, is_first_subscription_payment: true, kofi_transaction_id: 'm1' });
  const monthlyEnd = Date.parse(entitlement('pass@example.test').expiresAt);
  const response = await kofi({ type: 'Shop Order', email: 'pass@example.test', kofi_transaction_id: 's1', shop_items: [{ direct_link_code: 'ABC123DEF', quantity: 1 }] });
  assert.equal(JSON.parse(response.body).plan, 'yearly');
  const record = entitlement('pass@example.test');
  assert.equal(Date.parse(record.expiresAt) - monthlyEnd, 366 * DAY_MS);
  assert.equal(record.plan, 'yearly');
  assert.equal(record.tier, '12-month pass');
  const types = [...store('premium-member-emails').data.values()].map((job) => job.type).sort();
  assert.deepEqual(types, ['pass_ends_14', 'pass_ends_3', 'tips_day7', 'yearly_day20']);
});

test('tips and other shop items never unlock Premium', async () => {
  reset();
  const tip = await kofi({ type: 'Donation', email: 'tip@example.test', kofi_transaction_id: 'd1' });
  assert.equal(JSON.parse(tip.body).ignored, 'not_membership');
  const sticker = await kofi({ type: 'Shop Order', email: 'tip@example.test', kofi_transaction_id: 's2', shop_items: [{ direct_link_code: 'sticker', quantity: 3 }] });
  assert.equal(JSON.parse(sticker.body).ignored, 'not_membership');
  assert.equal(entitlement('tip@example.test'), undefined);
  assert.equal(webhook._test.passesInOrder({ shop_items: [{ direct_link_code: 'abc123def', quantity: 2 }, { direct_link_code: 'other999' }] }), 3);
});

test('give a month, get a month: rewarded once, on the first payment, within the yearly cap', async () => {
  reset();
  const owner = { email: 'owner@example.test', emailHash: sha256('owner@example.test') };
  const status = await referrals.referralStatus({}, owner);
  assert.match(status.code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal(status.link, `https://web.arvio.tv/?ref=${status.code}`);
  assert.equal((await referrals.referralStatus({}, owner)).code, status.code, 'the code is stable');

  assert.equal((await referrals.claimReferral({}, { emailHash: owner.emailHash, code: status.code })).error, 'own_code');
  assert.equal((await referrals.claimReferral({}, { emailHash: sha256('x@example.test'), code: 'NOPE' })).error, 'invalid_code');
  store('entitlements').data.set(`email/${sha256('member@example.test')}.json`, { status: 'active', source: 'kofi', startedAt: '2026-01-01', expiresAt: '2099-01-01' });
  assert.equal((await referrals.claimReferral({}, { emailHash: sha256('member@example.test'), code: status.code })).error, 'already_member');

  const friendHash = sha256('friend@example.test');
  assert.equal((await referrals.claimReferral({}, { emailHash: friendHash, code: status.code.toLowerCase() })).ok, true);
  assert.equal((await referrals.claimReferral({}, { emailHash: friendHash, code: status.code })).error, 'already_claimed');

  await kofi({ type: 'Subscription', email: 'friend@example.test', is_subscription_payment: true, is_first_subscription_payment: true, kofi_transaction_id: 'f1' });
  const friend = entitlement('friend@example.test');
  assert.ok(Date.parse(friend.expiresAt) - Date.now() > 61 * DAY_MS, 'friend: 31 paid + 31 bonus days');
  const inviter = entitlement('owner@example.test');
  assert.equal(inviter.status, 'active');
  assert.ok(Date.parse(inviter.expiresAt) - Date.now() > 30 * DAY_MS);
  assert.ok([...store('premium-member-emails').data.values()].some((job) => job.type === 'referral_reward'));

  await kofi({ type: 'Subscription', email: 'friend@example.test', is_subscription_payment: true, kofi_transaction_id: 'f2' });
  assert.equal(entitlement('owner@example.test').expiresAt, inviter.expiresAt, 'a renewal does not reward again');
  assert.equal((await referrals.referralStatus({}, owner)).joined, 1);

  const ownerRecord = store('premium-referrals').data.get(`owner/${owner.emailHash}.json`);
  ownerRecord.rewards = Array.from({ length: 6 }, () => new Date().toISOString());
  const second = sha256('second@example.test');
  await referrals.claimReferral({}, { emailHash: second, code: status.code });
  const before = entitlement('owner@example.test').expiresAt;
  const reward = await referrals.rewardReferralIfDue({}, { emailHash: second });
  assert.equal(reward.rewarded, true);
  assert.equal(reward.inviterRewarded, false, 'at most 6 free months a year for the inviter');
  assert.equal(entitlement('owner@example.test').expiresAt, before);
});

test('member emails are skipped when they no longer apply and can be unsubscribed', async () => {
  reset();
  const { stillRelevant, memberEmailContent, deliverMemberEmailJob } = memberEmails._test;
  const active = { status: 'active', source: 'kofi', plan: 'monthly', startedAt: '2026-10-01', expiresAt: new Date(NOW + 10 * DAY_MS).toISOString() };
  assert.equal(stillRelevant({ type: 'tips_day7' }, active, NOW), true);
  assert.equal(stillRelevant({ type: 'tips_day7' }, { ...active, expiresAt: new Date(NOW - 10 * DAY_MS).toISOString() }, NOW), false);
  assert.equal(stillRelevant({ type: 'yearly_day20' }, { ...active, plan: 'yearly' }, NOW), false);
  const target = active.expiresAt;
  assert.equal(stillRelevant({ type: 'pass_ends_3', targetEnd: target }, active, NOW), true);
  assert.equal(stillRelevant({ type: 'pass_ends_3', targetEnd: target }, { ...active, expiresAt: new Date(NOW + 300 * DAY_MS).toISOString() }, NOW), false, 'renewed passes get no reminder');

  const accountKey = memberEmails.memberAccountKey('a@example.test');
  const content = memberEmailContent('pass_ends_3', { accountKey, targetEnd: '2027-11-02T00:00:00Z' });
  assert.match(content.subject, /November 2, 2027/);
  assert.match(content.text, /member-email-optout\?a=[a-f0-9]{64}&s=[a-f0-9]{64}/);
  assert.equal(memberEmails.verifyOptout(accountKey, memberEmails._test.optoutSignature(accountKey)), true);
  assert.equal(memberEmails.verifyOptout(accountKey, 'f'.repeat(64)), false);

  const jobs = store('premium-member-emails');
  const entitlements = store('entitlements');
  entitlements.data.set(`email/${sha256('a@example.test')}.json`, active);
  await memberEmails.queueMemberEmail({}, { email: 'a@example.test', emailHash: sha256('a@example.test'), type: 'tips_day7', dueAt: NOW });
  const [key] = [...jobs.data.keys()];
  const sent = [];
  await memberEmails.optOut({}, accountKey);
  assert.equal(await deliverMemberEmailJob({}, jobs, key, jobs.data.get(key), { now: NOW, send: async (...args) => sent.push(args), entitlements }), false);
  assert.equal(sent.length, 0);
  assert.equal(jobs.data.get(key).status, 'suppressed');
  assert.equal(jobs.data.get(key).sealedEmail, null, 'the address is dropped once the job is done');
});

test('stream tickets: valid until expiry, useless when changed', () => {
  const { signTicket, verifyTicket, TICKET_TTL_SECONDS } = streamTicket._test;
  const secret = 's'.repeat(40);
  const now = 1_800_000_000;
  const { ticket } = signTicket(secret, 'abcdef1234', now);
  assert.equal(verifyTicket(secret, ticket, now + 60), true);
  assert.equal(verifyTicket(secret, ticket, now + TICKET_TTL_SECONDS + 1), false);
  assert.equal(verifyTicket('t'.repeat(40), ticket, now), false);
  const parts = ticket.split('.');
  assert.equal(verifyTicket(secret, [parts[0], String(now + 999999), parts[2], parts[3]].join('.'), now), false);
});

test('exit survey only accepts the listed reasons and trims free text', () => {
  assert.deepEqual(exitSurvey._test.REASONS, ['too_expensive', 'playback_problems', 'missing_feature', 'only_needed_briefly', 'use_android_instead', 'other']);
  assert.equal(exitSurvey._test.cleanDetail(` a\nb\t${'x'.repeat(400)}`).length, 300);
});
