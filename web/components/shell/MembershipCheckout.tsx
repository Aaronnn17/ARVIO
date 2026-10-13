"use client";

import { useEffect, useId, useRef, useState } from "react";
import { Copy, ExternalLink, Loader2, X } from "lucide-react";
import { useTranslation } from "@/lib/i18n";
import { authClient, useApp } from "@/lib/store";
import { ENTITLEMENT_REFRESH_EVENT, fetchEntitlement, kofiSubscribeUrl, type EntitlementState } from "@/lib/entitlement";
import { createPaymentRecovery } from "@/lib/paymentRecovery";
import { trackPremiumEvent } from "@/lib/premiumAnalytics";
import { BillingEmailForm } from "./BillingEmailForm";

export function MembershipCheckout({ children, className, entry, title, onEntitled }: {
  children: React.ReactNode; className?: string; entry: string; title?: string;
  onEntitled?: (state: EntitlementState) => void;
}) {
  const translateUi = useTranslation();
  const { auth, goToLogin } = useApp();
  const [open, setOpen] = useState(false);
  const [waiting, setWaiting] = useState(false);
  const [status, setStatus] = useState<"idle" | "checking" | "pending" | "active" | "error">("idle");
  const [copied, setCopied] = useState(false);
  const [preflightAttempt, setPreflightAttempt] = useState(0);
  const dialog = useRef<HTMLDialogElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const recovery = useRef<ReturnType<typeof createPaymentRecovery> | null>(null);
  const applied = useRef(onEntitled);
  applied.current = onEntitled;
  const id = useId();
  const accountId = auth?.userId;

  useEffect(() => {
    if (!open || !accountId) return;
    dialog.current?.showModal();
    return () => { dialog.current?.close(); trigger.current?.focus(); };
  }, [open, accountId]);
  useEffect(() => { setOpen(false); setWaiting(false); setStatus("idle"); setCopied(false); }, [accountId]);

  useEffect(() => {
    if (!open || waiting || !accountId) return;
    let current = true;
    setStatus("checking");
    void fetchEntitlement(authClient).then(next => {
      if (!current || authClient.session?.userId !== accountId) return;
      if (next.entitled && next.reason === "subscription") activate(next);
      else setStatus("idle");
    }).catch(() => { if (current && authClient.session?.userId === accountId) setStatus("error"); });
    return () => { current = false; };
  }, [open, waiting, accountId, preflightAttempt]);

  const activate = (state: EntitlementState) => {
    if (!state.entitled || state.reason !== "subscription") return;
    setStatus("active"); setWaiting(false);
    applied.current?.(state);
    window.dispatchEvent(new Event(ENTITLEMENT_REFRESH_EVENT));
  };

  useEffect(() => {
    if (!open || !waiting || !accountId) return;
    let returned = false;
    // The native external link can move focus before this effect is installed.
    let hasLeft = document.visibilityState === "hidden" || !document.hasFocus();
    const controller = createPaymentRecovery({
      check: () => fetchEntitlement(authClient),
      isCurrent: () => authClient.session?.userId === accountId,
      isVisible: () => document.visibilityState === "visible",
      onResult: (result, state) => {
        setStatus(result);
        if (result !== "checking") void trackPremiumEvent(authClient, "payment_status_checked", { entry, status: result });
        if (result === "active" && state) activate(state);
      }
    });
    recovery.current = controller;
    const onReturn = () => {
      if (document.visibilityState === "hidden") { hasLeft = true; return; }
      if (!hasLeft) return;
      if (!returned) { returned = true; void trackPremiumEvent(authClient, "checkout_returned", { entry }); }
      void controller.resume();
    };
    const onLeave = () => { hasLeft = true; };
    const onFocus = () => { hasLeft = true; onReturn(); };
    window.addEventListener("focus", onFocus);
    window.addEventListener("blur", onLeave);
    document.addEventListener("visibilitychange", onReturn);
    return () => {
      controller.stop(); recovery.current = null;
      window.removeEventListener("focus", onFocus);
      window.removeEventListener("blur", onLeave);
      document.removeEventListener("visibilitychange", onReturn);
    };
  }, [open, waiting, accountId, entry]);

  return <>
    <button ref={trigger} type="button" className={className} title={title} aria-label={title} onClick={() => {
      if (!auth) { goToLogin(); return; }
      setOpen(true);
    }}>{children}</button>
    {open && auth && <dialog ref={dialog} className="membership-checkout" aria-labelledby={`${id}-title`} onCancel={() => setOpen(false)}>
      <button type="button" className="membership-close" aria-label={translateUi("Close")} onClick={() => setOpen(false)}><X size={20} /></button>
      <h2 id={`${id}-title`}>{translateUi("Keep your ARVIO Web access")}</h2>
      <p>{translateUi("$2.99/month for managed browser hosting. Your Android app stays free. Media and third-party subscriptions are not included.")}</p>
      <p>{translateUi("Test your own sources during the free trial. Subscribing does not fix an incompatible source.")}</p>
      <div className="membership-email">
        <span>{translateUi("Use this email at checkout")}</span><strong>{auth.email}</strong>
        <button type="button" className="paywall-trial" onClick={async () => {
          try { await navigator.clipboard.writeText(auth.email); setCopied(true); } catch { setCopied(false); }
        }}><Copy size={15} /> {translateUi(copied ? "Copied" : "Copy email")}</button>
      </div>
      <p>{translateUi("PayPal or Ko-fi may use a different email. You can securely link that email here after paying.")}</p>
      {status !== "active" && status !== "checking" && status !== "error" && <a className={waiting ? "paywall-trial" : "paywall-primary"} href={kofiSubscribeUrl()} target="_blank" rel="noopener noreferrer" onClick={() => {
        setWaiting(true); setStatus("pending");
        void trackPremiumEvent(authClient, "checkout_opened", { entry });
      }}>{translateUi(waiting ? "Return to Ko-fi" : "Continue to Ko-fi — $2.99/month")} <ExternalLink size={16} /></a>}
      {waiting && <p>{translateUi("Finish on Ko-fi, then return to this tab. We will check your access automatically. Do not pay again if activation is delayed.")}</p>}
      <p role="status" aria-live="polite">
        {status === "checking" && <Loader2 size={16} className="paywall-spinner" />}
        {translateUi(status === "active" ? "Your Premium membership is active." : status === "checking" ? "Checking your payment status…" : status === "error" ? "Could not check access. Your payment status has not changed; please retry." : waiting ? "No paid membership found yet. Check again or link the email on your receipt." : "After payment, come back here to confirm activation.")}
      </p>
      {waiting && <button type="button" className="paywall-trial" disabled={status === "checking"} onClick={() => { void recovery.current?.retry(); }}>{translateUi("Check payment status")}</button>}
      {!waiting && status === "error" && <button type="button" className="paywall-trial" onClick={() => setPreflightAttempt(value => value + 1)}>{translateUi("Check payment status")}</button>}
      {status !== "active" && <BillingEmailForm key={`${accountId}:${waiting}`} initiallyOpen={waiting} onEntitled={activate} />}
      {status === "active" && <button type="button" className="paywall-primary" onClick={() => setOpen(false)}>{translateUi("Continue watching")}</button>}
    </dialog>}
  </>;
}
