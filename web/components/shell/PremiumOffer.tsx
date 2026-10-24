"use client";

import { useEffect, useId, useRef, useState } from "react";
import { BadgeCheck, ExternalLink, Loader2, RefreshCw, X } from "lucide-react";
import { useTranslation } from "@/lib/i18n";
import { authClient } from "@/lib/store";
import { EXIT_REASONS, kofiYearlyUrl, submitExitSurvey, type EntitlementState, type ExitReason } from "@/lib/entitlement";
import type { PremiumIntent } from "@/lib/premiumGate";
import { config } from "@/lib/config";
import { MembershipCheckout } from "./MembershipCheckout";

const DISCORD_URL = "https://discord.gg/UavuEYMfQ4";

export function deviceName(userAgent = typeof navigator === "undefined" ? "" : navigator.userAgent, touchPoints = typeof navigator === "undefined" ? 0 : navigator.maxTouchPoints): string {
  if (/iPhone|iPod/i.test(userAgent)) return "iPhone";
  if (/iPad/i.test(userAgent) || (/Macintosh/i.test(userAgent) && touchPoints > 1)) return "iPad";
  if (/Macintosh|Mac OS X/i.test(userAgent)) return "Mac";
  if (/Android/i.test(userAgent)) return "phone";
  if (/Windows|Linux|CrOS/i.test(userAgent)) return "computer";
  return "device";
}

// Literal phrases so the translation tooling can find them.
function headline(intent: PremiumIntent): string {
  if (intent === "live") return "Watch Live TV on your {device}";
  if (intent === "download") return "Download with ARVIO Premium";
  if (intent === "external" || intent === "copy") return "Open streams with ARVIO Premium";
  return "Watch this on your {device}";
}

const DEVICE_LABELS: Record<string, string> = { iPhone: "iPhone", iPad: "iPad", Mac: "Mac", phone: "phone", computer: "computer", device: "device" };

const REASON_LABELS: Record<ExitReason, string> = {
  too_expensive: "Too expensive",
  playback_problems: "Playback didn't work well",
  missing_feature: "A feature I needed was missing",
  only_needed_briefly: "I only needed it for a while",
  use_android_instead: "I use the Android app instead",
  other: "Something else"
};

function surveyKey(state: EntitlementState | null, account: string | null) {
  return account ? `arvio.exitsurvey:${account}:${state?.expiresAt ?? ""}` : null;
}

// Asked once per lapsed membership: why did you stop?
function ExitSurvey({ state, account }: { state: EntitlementState | null; account: string | null }) {
  const translateUi = useTranslation();
  const key = surveyKey(state, account);
  const [done, setDone] = useState(() => { try { return !key || Boolean(localStorage.getItem(key)); } catch { return true; } });
  const [reason, setReason] = useState<ExitReason | null>(null);
  const [detail, setDetail] = useState("");
  const [sending, setSending] = useState(false);
  const id = useId();
  if (done) return null;
  const finish = () => { try { if (key) localStorage.setItem(key, "1"); } catch { /* optional */ } setDone(true); };
  return <form className="premium-exit-survey" aria-labelledby={`${id}-q`} onSubmit={async (event) => {
    event.preventDefault();
    if (!reason) return;
    setSending(true);
    await submitExitSurvey(authClient, reason, detail).catch(() => null);
    setSending(false);
    finish();
  }}>
    <p id={`${id}-q`} className="premium-exit-question">{translateUi("Your membership ended. What made you stop?")}</p>
    <div className="premium-exit-reasons" role="radiogroup" aria-labelledby={`${id}-q`}>
      {EXIT_REASONS.map((value) => <button type="button" key={value} role="radio" aria-checked={reason === value} onClick={() => setReason(value)}>{translateUi(REASON_LABELS[value])}</button>)}
    </div>
    {reason && <>
      <label className="premium-exit-detail"><span>{translateUi("Anything else? (optional)")}</span>
        <textarea value={detail} maxLength={300} rows={2} onChange={(event) => setDetail(event.target.value)} />
      </label>
      <div className="premium-exit-actions">
        <button type="submit" className="paywall-trial" disabled={sending}>{sending ? <Loader2 size={15} className="paywall-spinner" /> : null}{translateUi("Send")}</button>
        <button type="button" className="paywall-link-toggle" onClick={finish}>{translateUi("Skip")}</button>
      </div>
    </>}
  </form>;
}

export function PremiumOffer({ intent, state, status, account, onClose, onRetry, onEntitled }: {
  intent: PremiumIntent;
  state: EntitlementState | null;
  status: "loading" | "ready" | "error";
  account: string | null;
  onClose: () => void;
  onRetry: () => void;
  onEntitled: (next: EntitlementState) => void;
}) {
  const translateUi = useTranslation();
  const dialog = useRef<HTMLDialogElement>(null);
  const id = useId();
  const yearly = kofiYearlyUrl();
  const device = deviceName();
  const lapsed = Boolean(state?.everPaid) && !state?.entitled;

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
    return () => element?.close();
  }, []);

  return <dialog ref={dialog} className="premium-offer" aria-labelledby={`${id}-title`} onCancel={(event) => { event.preventDefault(); onClose(); }}>
    <button type="button" className="membership-close" aria-label={translateUi("Close")} onClick={onClose}><X size={20} /></button>
    {status === "loading" && !state ? <div className="premium-offer-checking" role="status">
      <Loader2 size={28} className="paywall-spinner" />
      <p>{translateUi("Checking your membership…")}</p>
    </div> : status === "error" ? <div role="alert">
      <h2 id={`${id}-title`}>{translateUi("We could not check your membership")}</h2>
      <p>{translateUi("Your payment status has not changed. Please retry before subscribing again.")}</p>
      <button type="button" className="paywall-primary" onClick={onRetry}><RefreshCw size={16} /> {translateUi("Check access again")}</button>
    </div> : <>
      <p className="premium-offer-eyebrow"><BadgeCheck size={15} /> ARVIO PREMIUM</p>
      <h2 id={`${id}-title`}>{translateUi(headline(intent), { device: translateUi(DEVICE_LABELS[device] ?? "device") })}</h2>
      <p className="premium-offer-lead">{translateUi("Everything you set up stays. Premium unlocks playback, Live TV and downloads in ARVIO Web on every browser you sign in to.")}</p>
      <div className={`premium-offer-plans${yearly ? "" : " single"}`}>
        {yearly && <div className="premium-offer-plan best">
          <p className="premium-offer-badge">{translateUi("Best value · save 44%")}</p>
          <p className="premium-offer-price"><strong>$20</strong> <span>{translateUi("/ 12 months")}</span></p>
          <p className="premium-offer-terms">{translateUi("One payment, no automatic renewal. About $1.67 a month.")}</p>
          <MembershipCheckout className="paywall-primary" entry={`explore_${intent}_yearly`} href={yearly} onEntitled={onEntitled} showEmailHint>
            {translateUi("Get the 12-month pass")} <ExternalLink size={15} />
          </MembershipCheckout>
        </div>}
        <div className="premium-offer-plan">
          <p className="premium-offer-price"><strong>$2.99</strong> <span>{translateUi("/ month")}</span></p>
          <p className="premium-offer-terms">{translateUi("Monthly membership. Cancel anytime through Ko-fi.")}</p>
          <MembershipCheckout className={yearly ? "paywall-trial" : "paywall-primary"} entry={`explore_${intent}_monthly`} onEntitled={onEntitled} showEmailHint={!yearly}>
            {translateUi("Subscribe monthly")} <ExternalLink size={15} />
          </MembershipCheckout>
        </div>
      </div>
      <p className="premium-offer-refund">{translateUi("Doesn't work on your device? Message us within 7 days for a full refund.")} <a href={DISCORD_URL} target="_blank" rel="noopener noreferrer">Discord</a></p>
      {/* Members who left already know the app: the video is for newcomers. */}
      {!lapsed && config.promoVideoUrl && <video className="premium-offer-video" src={config.promoVideoUrl} poster={config.promoPosterUrl || undefined} muted playsInline controls preload="none" />}
      {lapsed && <ExitSurvey state={state} account={account} />}
      <p className="premium-offer-note">{translateUi("The Android and TV app stays free. Membership does not include media or subscriptions to other services.")}</p>
    </>}
  </dialog>;
}
