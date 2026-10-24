// POST /kofi-webhook  ← Ko-fi calls this on every payment.
// Ko-fi sends application/x-www-form-urlencoded with a single `data` field
// containing a JSON string. We verify Ko-fi's verification_token against our
// secret, then grant/renew web access for the buyer's email.
//
// Two ways to pay:
//   - Monthly membership (type "Subscription"): KOFI_MEMBERSHIP_DAYS (default
//     31) per payment.
//   - 12-month pass (type "Shop Order" for one of KOFI_YEARLY_ITEM_CODES, the
//     Ko-fi Shop item's direct link code(s), comma separated): 366 days per
//     pass bought.
// Either way the new time is added on top of any paid time still ahead.
//
// Env required: KOFI_VERIFICATION_TOKEN (from Ko-fi → Settings → Webhooks/API).
// Optional:     KOFI_MEMBERSHIP_DAYS, KOFI_YEARLY_ITEM_CODES, KOFI_YEARLY_URL
//               (used in emails).
const { json, options, normalizeEmail, sha256 } = require("./_backend");
const {
  entitlementsStore,
  readEntitlement,
  writeEntitlement,
  buildPaidRecord
} = require("./_entitlements");
const { recordPremiumEvent } = require("./_premium-funnel");
const { queueForPayment } = require("./_member-emails");
const { rewardReferralIfDue } = require("./_referrals");

const PASS_DAYS = 366;
const MAX_REMEMBERED_PAYMENTS = 40;

function parseKofiData(event) {
  // Ko-fi posts form-urlencoded: data=<url-encoded JSON string>.
  const raw = event.isBase64Encoded ? Buffer.from(event.body || "", "base64").toString("utf8") : (event.body || "");
  const params = new URLSearchParams(raw);
  const dataField = params.get("data");
  if (!dataField) {
    // Some setups post raw JSON; tolerate that too.
    try { return JSON.parse(raw); } catch { return null; }
  }
  try { return JSON.parse(dataField); } catch { return null; }
}

function yearlyItemCodes() {
  return new Set(String(process.env.KOFI_YEARLY_ITEM_CODES || "")
    .split(",").map((code) => code.trim().toLowerCase()).filter(Boolean));
}

// How many 12-month passes a Shop Order contains (0 when it is something else).
function passesInOrder(data) {
  const codes = yearlyItemCodes();
  if (!codes.size || !Array.isArray(data.shop_items)) return 0;
  return data.shop_items.reduce((total, item) => {
    if (!item || !codes.has(String(item.direct_link_code || "").trim().toLowerCase())) return total;
    const quantity = Math.floor(Number(item.quantity || 1));
    return total + (Number.isFinite(quantity) && quantity > 0 ? Math.min(quantity, 5) : 1);
  }, 0);
}

function paymentId(data) {
  return String(data.kofi_transaction_id || data.message_id || "").trim().slice(0, 100) || null;
}

exports.handler = async (event) => {
  const cors = options(event);
  if (cors) return cors;
  if (event.httpMethod !== "POST") return json(405, { error: "method_not_allowed" });

  const expectedToken = process.env.KOFI_VERIFICATION_TOKEN || "";
  if (!expectedToken) {
    console.error("kofi-webhook: KOFI_VERIFICATION_TOKEN not configured");
    return json(500, { error: "not_configured" });
  }

  const data = parseKofiData(event);
  if (!data || typeof data !== "object") {
    return json(400, { error: "bad_payload" });
  }

  // Verify this really came from OUR Ko-fi account.
  if (String(data.verification_token || "") !== expectedToken) {
    return json(401, { error: "invalid_verification_token" });
  }

  const email = normalizeEmail(data.email);
  if (!email) {
    // No email to attach the entitlement to — accept (200) so Ko-fi doesn't
    // retry forever, but record nothing.
    return json(200, { ok: true, ignored: "no_email" });
  }

  // Only memberships and the 12-month pass grant access. A one-off tip or any
  // other shop item does not.
  const type = String(data.type || "").toLowerCase();
  const isSubscription = data.is_subscription_payment === true || type === "subscription";
  const passes = type === "shop order" ? passesInOrder(data) : 0;
  if (!isSubscription && !passes) {
    return json(200, { ok: true, ignored: "not_membership", type });
  }
  const plan = passes ? "yearly" : "monthly";
  const isFirstSub = isSubscription && data.is_first_subscription_payment === true;

  try {
    const store = entitlementsStore(event);
    const emailHash = sha256(email);
    const existing = await readEntitlement(store, emailHash);

    // Ko-fi retries a webhook it thinks failed. Paid time is now added on top
    // of time already paid, so a repeated delivery must not grant twice.
    const id = paymentId(data);
    const processed = Array.isArray(existing?.payments) ? existing.payments : [];
    if (id && processed.includes(id)) {
      return json(200, { ok: true, duplicate: true, expiresAt: existing.expiresAt || null });
    }

    const days = passes ? PASS_DAYS * passes : Number(process.env.KOFI_MEMBERSHIP_DAYS || 31);
    const firstPayment = !existing || existing.source === "trial" || !existing.startedAt;
    const record = buildPaidRecord(existing, {
      source: "kofi",
      tier: passes ? "12-month pass" : (data.tier_name || (existing && existing.tier) || null),
      plan,
      days,
      event: passes ? "kofi-pass-purchased" : isFirstSub ? "kofi-subscription-started" : "kofi-subscription-renewed"
    });
    if (id) record.payments = [...processed, id].slice(-MAX_REMEMBERED_PAYMENTS);
    await writeEntitlement(store, emailHash, record);

    await recordPremiumEvent(event, {
      email,
      eventName: passes || isFirstSub ? "subscription_started" : "subscription_renewed",
      metadata: { source: "kofi", tier: passes ? "12-month pass" : (data.tier_name || "membership") }
    }).catch((error) => console.error("kofi funnel recording failed", error));

    // Side effects that must never fail the payment itself.
    await queueForPayment(event, { email, emailHash, plan, firstPayment: firstPayment || isFirstSub, record })
      .catch((error) => console.error("member emails not queued", error && error.message));
    await rewardReferralIfDue(event, { emailHash })
      .catch((error) => console.error("referral reward failed", error && error.message));

    return json(200, { ok: true, entitled: true, plan, expiresAt: record.expiresAt });
  } catch (error) {
    console.error("kofi-webhook failed", error);
    // 500 → Ko-fi will retry, which is what we want on a transient storage error.
    return json(500, { error: "kofi_webhook_failed", message: error.message });
  }
};

exports._test = { passesInOrder, paymentId, yearlyItemCodes };
