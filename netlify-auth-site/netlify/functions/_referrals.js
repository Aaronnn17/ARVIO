// "Give a month, get a month". Every account can get an invite code. Someone
// who signs up through it and makes a first payment earns 31 extra days for
// both accounts; the inviter can earn at most MAX_REWARDS_PER_YEAR a year.
//
// Store "premium-referrals":
//   code/<CODE>.json         { ownerHash, createdAt }
//   owner/<ownerHash>.json   { code, sealedEmail, rewards: [ISO], joined }
//   referred/<emailHash>.json { code, ownerHash, claimedAt, rewardedAt? }
// ownerHash / emailHash = sha256(email), the same key as the entitlement
// record, so a reward can extend the right membership directly.
const crypto = require("crypto");
const { connectLambda, getStore } = require("@netlify/blobs");
const { entitlementsStore, readEntitlement, writeEntitlement, evaluateEntitlement, buildPaidRecord, DAY_MS } = require("./_entitlements");
const { queueMemberEmail, _test: memberEmailInternals } = require("./_member-emails");

const REWARD_DAYS = 31;
const MAX_REWARDS_PER_YEAR = 6;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{8}$/;

function referralStore(event) {
  connectLambda(event);
  return getStore("premium-referrals");
}

function newCode() {
  const bytes = crypto.randomBytes(8);
  return Array.from(bytes, (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

function normalizeCode(value) {
  const code = String(value || "").trim().toUpperCase();
  return CODE_PATTERN.test(code) ? code : null;
}

function inviteLink(code) {
  return `https://web.arvio.tv/?ref=${code}`;
}

async function getJSON(store, key) {
  try {
    return await store.get(key, { type: "json", consistency: "strong" });
  } catch (error) {
    if (String(error?.message || "").includes("uncachedEdgeURL")) return store.get(key, { type: "json" }).catch(() => null);
    if (error?.status === 404 || error?.name === "BlobNotFoundError") return null;
    throw error;
  }
}

function rewardsInLastYear(owner, now = Date.now()) {
  return (owner?.rewards || []).filter((at) => now - Date.parse(at) < 365 * DAY_MS).length;
}

// The account's invite code, created on first request.
async function ensureOwner(store, { email, emailHash }) {
  const existing = await getJSON(store, `owner/${emailHash}.json`);
  if (existing?.code) return existing;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = newCode();
    const claimed = await store.setJSON(`code/${code}.json`, { ownerHash: emailHash, createdAt: new Date().toISOString() }, { onlyIfNew: true });
    if (claimed?.modified === false) continue;
    const owner = { code, sealedEmail: memberEmailInternals.sealEmail(email), rewards: [], joined: 0, createdAt: new Date().toISOString() };
    const written = await store.setJSON(`owner/${emailHash}.json`, owner, { onlyIfNew: true });
    if (written?.modified === false) {
      // Another request created it first; keep theirs.
      await store.delete(`code/${code}.json`).catch(() => {});
      return getJSON(store, `owner/${emailHash}.json`);
    }
    return owner;
  }
  throw new Error("Could not allocate an invite code");
}

async function referralStatus(event, { email, emailHash }, now = Date.now()) {
  const store = referralStore(event);
  const owner = await ensureOwner(store, { email, emailHash });
  const used = rewardsInLastYear(owner, now);
  return {
    code: owner.code,
    link: inviteLink(owner.code),
    joined: owner.joined || 0,
    rewardsThisYear: used,
    rewardsLeftThisYear: Math.max(0, MAX_REWARDS_PER_YEAR - used),
    rewardDays: REWARD_DAYS,
    maxRewardsPerYear: MAX_REWARDS_PER_YEAR
  };
}

// Record that this account signed up through an invite. Only accounts that
// have never paid can be invited, an account cannot invite itself, and the
// first claim wins.
async function claimReferral(event, { emailHash, code }, { entitlements } = {}) {
  const normalized = normalizeCode(code);
  if (!normalized) return { ok: false, error: "invalid_code" };
  const store = referralStore(event);
  const codeRecord = await getJSON(store, `code/${normalized}.json`);
  if (!codeRecord?.ownerHash) return { ok: false, error: "unknown_code" };
  if (codeRecord.ownerHash === emailHash) return { ok: false, error: "own_code" };
  const record = await readEntitlement(entitlements || entitlementsStore(event), emailHash);
  if (evaluateEntitlement(record).everPaid) return { ok: false, error: "already_member" };
  const written = await store.setJSON(`referred/${emailHash}.json`, { code: normalized, ownerHash: codeRecord.ownerHash, claimedAt: new Date().toISOString() }, { onlyIfNew: true });
  if (written?.modified === false) return { ok: false, error: "already_claimed" };
  return { ok: true };
}

// Called after a payment for `emailHash` (the payer, or the ARVIO account a
// payment was linked to). Rewards both accounts once.
async function rewardReferralIfDue(event, { emailHash, now = Date.now() }, { entitlements } = {}) {
  const store = referralStore(event);
  const snapshot = await store.getWithMetadata(`referred/${emailHash}.json`, { type: "json", consistency: "strong" }).catch(() => null);
  const referred = snapshot?.data;
  if (!referred || referred.rewardedAt) return { rewarded: false };
  const marked = await store.setJSON(`referred/${emailHash}.json`, { ...referred, rewardedAt: new Date(now).toISOString() }, { onlyIfMatch: snapshot.etag });
  if (marked?.modified === false) return { rewarded: false };

  const entitlementStore = entitlements || entitlementsStore(event);
  const friend = await readEntitlement(entitlementStore, emailHash);
  await writeEntitlement(entitlementStore, emailHash, buildPaidRecord(friend, { source: friend?.source || "referral", days: REWARD_DAYS, event: "referral-bonus-invited", now }));

  const owner = await getJSON(store, `owner/${referred.ownerHash}.json`);
  const ownerUpdate = { ...(owner || {}), joined: Number(owner?.joined || 0) + 1 };
  let inviterRewarded = false;
  if (owner && rewardsInLastYear(owner, now) < MAX_REWARDS_PER_YEAR) {
    const inviter = await readEntitlement(entitlementStore, referred.ownerHash);
    await writeEntitlement(entitlementStore, referred.ownerHash, buildPaidRecord(inviter, { source: inviter?.source || "referral", days: REWARD_DAYS, event: "referral-bonus-inviter", now }));
    ownerUpdate.rewards = [...(owner.rewards || []), new Date(now).toISOString()].slice(-24);
    inviterRewarded = true;
    if (owner.sealedEmail) {
      try {
        const inviterEmail = memberEmailInternals.openEmail(owner.sealedEmail);
        await queueMemberEmail(event, { email: inviterEmail, emailHash: referred.ownerHash, type: "referral_reward", dueAt: now, targetEnd: new Date(now).toISOString() });
      } catch (error) {
        console.error("referral reward email not queued", error && error.message);
      }
    }
  }
  await store.setJSON(`owner/${referred.ownerHash}.json`, ownerUpdate);
  return { rewarded: true, inviterRewarded };
}

async function deleteReferralData(event, emailHash) {
  const store = referralStore(event);
  const owner = await getJSON(store, `owner/${emailHash}.json`);
  if (owner?.code) await store.delete(`code/${owner.code}.json`).catch(() => {});
  await store.delete(`owner/${emailHash}.json`).catch(() => {});
  await store.delete(`referred/${emailHash}.json`).catch(() => {});
}

module.exports = {
  REWARD_DAYS,
  MAX_REWARDS_PER_YEAR,
  normalizeCode,
  inviteLink,
  referralStatus,
  claimReferral,
  rewardReferralIfDue,
  deleteReferralData,
  _test: { newCode, rewardsInLastYear, ensureOwner }
};
