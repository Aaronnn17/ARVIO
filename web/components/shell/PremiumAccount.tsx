"use client";
import { useTranslation } from "@/lib/i18n";


import { BadgeCheck, ExternalLink, Loader2, RefreshCw } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { authClient, useApp } from "@/lib/store";
import { useEntitlement } from "@/lib/entitlementContext";
import { ENTITLEMENT_REFRESH_EVENT, fetchEntitlement, type EntitlementState } from "@/lib/entitlement";
import { config } from "@/lib/config";
import { HttpError } from "@/lib/http";
import { requestSourceSettings, sourceSetupState } from "@/lib/sourceSetup";
import { BillingEmailForm } from "./BillingEmailForm";
import { MembershipCheckout } from "./MembershipCheckout";

export function PremiumAccount() {
  const translateUi = useTranslation();
  const { auth, goToLogin, addons, addonsReady, settings, setSection } = useApp();
  const entitlement = useEntitlement();
  const [state, setState] = useState(entitlement);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pending = useRef(false);
  useEffect(() => { setState(entitlement); setMessage(""); }, [auth?.userId, entitlement]);
  if (!config.paywallEnabled || !auth) return null;
  const trial = state?.reason === "trial";
  const paid = state?.entitled && state.reason === "subscription";
  const applied = (next: EntitlementState) => {
    setState(next);
    setMessage(next.reason === "subscription" ? "Your Premium membership is active." : "Your trial is active. If you have paid, check your billing email below; do not pay again.");
    window.dispatchEvent(new Event(ENTITLEMENT_REFRESH_EVENT));
  };
  const check = async () => {
    if (pending.current) return;
    pending.current = true; setBusy(true); setMessage("");
    const account = auth.userId;
    try {
      const next = await fetchEntitlement(authClient);
      if (authClient.session?.userId !== account) return;
      if (next.entitled) applied(next);
      else setMessage("Payment has not arrived yet. Try again shortly or link the email on your Ko-fi receipt. Do not pay again.");
    } catch (error) {
      if (authClient.session?.userId !== account) return;
      if (error instanceof HttpError && error.status === 401) goToLogin();
      else setMessage("Could not check access. Your payment status has not changed; please retry.");
    } finally { pending.current = false; setBusy(false); }
  };
  return <section className="premium-account" aria-labelledby="premium-account-title">
    <h2 id="premium-account-title"><BadgeCheck size={20} /> {translateUi(" ARVIO Web Premium")}</h2>
    <p className="premium-account-status">{paid ? translateUi("Membership active") : trial ? translateUi("Free trial active") : translateUi("Check membership")}</p>
    <p className="premium-account-email">{auth.email}</p>
    {state?.expiresAt && <p>{trial ? translateUi("Trial ends") : translateUi("Access until")}: {new Date(state.expiresAt).toLocaleString()}</p>}
    <p>{translateUi("Browser access on iPhone, iPad, Windows, Mac and Linux. The Android app and Cloud dashboard remain free.")}</p>
    {trial && <div className="premium-trial-next">
      <h3>{translateUi("Make the most of your trial")}</h3>
      <p>{translateUi(addonsReady && sourceSetupState(addons, settings).hasAny ? "A media source is configured. Try a film or episode, including audio and subtitles, before subscribing." : "First connect your own media source. Catalogs alone do not provide playback.")}</p>
      <div className="premium-account-actions">
        <button type="button" className="paywall-trial" onClick={() => setSection("addons")}>{translateUi("Addons")}</button>
        <button type="button" className="paywall-trial" onClick={() => { requestSourceSettings("homeserver"); setSection("settings"); }}>{translateUi("Home Server")}</button>
      </div>
      <p>{translateUi("Your trial ends automatically. You will not be charged unless you subscribe on Ko-fi.")}</p>
    </div>}
    <div className="premium-account-actions">
      {!paid && <MembershipCheckout className="paywall-primary" entry="account_settings" onEntitled={applied}>
        {translateUi("Keep Premium - $2.99/month ")}<ExternalLink size={15} />
      </MembershipCheckout>}
      <button type="button" className="paywall-trial" disabled={busy} onClick={() => void check()}>
        {busy ? <Loader2 size={16} className="paywall-spinner" /> : <RefreshCw size={16} />} {translateUi(" Check payment status")}</button>
    </div>
    <BillingEmailForm key={auth.userId} onEntitled={applied} />
    {message && <p role="status">{translateUi(message)}</p>}
  </section>;
}
