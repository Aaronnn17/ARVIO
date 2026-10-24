import type { AuthClient } from "./auth";
import { fetchStreamTicket } from "./entitlement";

// A short-lived signed ticket from the auth site that lets the resolver
// worker's /media relay serve this Premium account. Kept in memory only; it
// is refreshed well before it expires and dropped when access ends.
let ticket: { value: string; expiresAt: number; account: string } | null = null;
let inflight: Promise<void> | null = null;

const REFRESH_MARGIN_MS = 60 * 60 * 1000;

/** The current ticket, or "" (the relay then decides). The Premium gate
 *  clears it whenever the account changes or access ends. */
export function currentStreamTicket(): string {
  if (!ticket || ticket.expiresAt <= Date.now()) return "";
  return ticket.value;
}

export function clearStreamTicket() {
  ticket = null;
}

/** Fetch or refresh the ticket. Failures are quiet: without a configured
 *  secret the relay does not ask for one. */
export function refreshStreamTicket(auth: AuthClient): Promise<void> {
  const account = auth.session?.userId;
  if (!account) { ticket = null; return Promise.resolve(); }
  if (ticket && ticket.account === account && ticket.expiresAt - Date.now() > REFRESH_MARGIN_MS) return Promise.resolve();
  if (inflight) return inflight;
  inflight = fetchStreamTicket(auth)
    .then((next) => {
      const expiresAt = Date.parse(next.expiresAt);
      if (next.ticket && Number.isFinite(expiresAt) && auth.session?.userId === account) ticket = { value: next.ticket, expiresAt, account };
    })
    .catch(() => { /* not configured, not Premium or offline: playback proceeds without */ })
    .finally(() => { inflight = null; });
  return inflight;
}
