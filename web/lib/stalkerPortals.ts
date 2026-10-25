// Stalker/Ministra portals in the Android app's multi-portal shape
// (iptvByProfile.<id>.stalkerPortals, see StalkerPortalSupport.kt):
//   - up to three portals, ids "stalker1".."stalker3";
//   - channel ids `stalker:<portalId>:<channelId>`, category keys `<portalId>|<group>`;
//   - the old single-portal fields (stalkerPortalUrl / stalkerMacAddress) become
//     "Portal 1", and old `stalker|<group>` keys become `stalker1|<group>`.
import type { AppSettings, StalkerPortalEntry } from "./types";

export const MAX_STALKER_PORTALS = 3;
/** Playlist id the single-portal builds used for every Stalker channel and category key. */
export const LEGACY_STALKER_ID = "stalker";

type PortalSettings = Pick<AppSettings, "iptvStalkerUrl" | "iptvStalkerMac"> & Partial<Pick<AppSettings, "iptvStalkerPortals">>;

const invisible = /[​-‍⁠﻿]/g;
const text = (value: unknown) => (typeof value === "string" ? value : "").replace(invisible, "").trim();

/** Android's normalisation: trimmed URL without a trailing slash, upper-case MAC. */
export function normalizePortalUrl(value: unknown) { return text(value).replace(/\/+$/, ""); }
export function normalizePortalMac(value: unknown) { return text(value).toUpperCase(); }

/** The next free "stalkerN" id (StalkerPortalSupport.nextAvailablePortalId), or null when the list is full. */
export function nextStalkerPortalId(existing: readonly string[], max = MAX_STALKER_PORTALS): string | null {
  const used = new Set(existing.map((id) => id.trim()));
  if (max <= 0 || used.size >= max) return null;
  let suffix = Math.max(0, ...[...used].map((id) => Number(id.replace(/^stalker/, ""))).filter((n) => Number.isInteger(n) && n > 0)) + 1;
  while (used.has(`stalker${suffix}`)) suffix++;
  return `stalker${suffix}`;
}

/**
 * Read a synced portal list. Entries without an address or MAC are dropped
 * (Android drops them too); every other field of an entry is kept as it was.
 */
export function normalizeStalkerPortals(value: unknown): StalkerPortalEntry[] {
  if (!Array.isArray(value)) return [];
  const used = new Set<string>();
  const result: StalkerPortalEntry[] = [];
  value.forEach((raw, index) => {
    if (result.length >= MAX_STALKER_PORTALS || !raw || typeof raw !== "object") return;
    const entry = raw as Record<string, unknown>;
    const portalUrl = normalizePortalUrl(entry.portalUrl);
    const macAddress = normalizePortalMac(entry.macAddress);
    if (!portalUrl || !macAddress) return;
    const wanted = text(entry.id) || `stalker${index + 1}`;
    const id = used.has(wanted) ? nextStalkerPortalId([...used]) : wanted;
    if (!id) return;
    used.add(id);
    result.push({ ...entry, id, name: text(entry.name) || `Portal ${index + 1}`, portalUrl, macAddress, enabled: entry.enabled !== false });
  });
  return result;
}

/** The single-portal fields as Portal 1 (StalkerPortalSupport.migratedPortalFromLegacy). */
export function legacyStalkerPortal(url: unknown, mac: unknown): StalkerPortalEntry | null {
  const portalUrl = normalizePortalUrl(url);
  const macAddress = normalizePortalMac(mac);
  return portalUrl && macAddress ? { id: "stalker1", name: "Portal 1", portalUrl, macAddress, enabled: true } : null;
}

/** Android's import rule: the list when it has entries, otherwise the legacy single portal. */
export function portalsFromCloud(list: unknown, legacyUrl: unknown, legacyMac: unknown): StalkerPortalEntry[] {
  const portals = normalizeStalkerPortals(list);
  if (portals.length) return portals;
  const legacy = legacyStalkerPortal(legacyUrl, legacyMac);
  return legacy ? [legacy] : [];
}

/** Every configured portal, enabled or not. */
export function stalkerPortalsOf(settings: PortalSettings): StalkerPortalEntry[] {
  if (settings.iptvStalkerPortals) return settings.iptvStalkerPortals;
  const legacy = legacyStalkerPortal(settings.iptvStalkerUrl, settings.iptvStalkerMac);
  return legacy ? [legacy] : [];
}

/** Portals that fill Live TV: enabled, complete, and live TV import not switched off (activeStalkerLiveTvPortals). */
export function liveTvStalkerPortals(settings: PortalSettings): StalkerPortalEntry[] {
  return stalkerPortalsOf(settings).filter((portal) => portal.enabled !== false && portal.portalUrl.trim() && portal.macAddress.trim() && portal.importLiveTv !== false);
}

export function hasStalkerPortals(settings: PortalSettings) {
  return liveTvStalkerPortals(settings).length > 0;
}

/** Part of the Live TV source signature: changes when a loading portal is added, removed or edited. */
export function stalkerSourceSignature(settings: PortalSettings): string {
  const portals = liveTvStalkerPortals(settings);
  return portals.length ? JSON.stringify(portals.map((portal) => [portal.id, portal.portalUrl, portal.macAddress])) : "";
}

/** Settings patch for a new portal list, keeping the legacy fields on the first enabled portal for older apps. */
export function stalkerPortalsPatch(portals: StalkerPortalEntry[]): Pick<AppSettings, "iptvStalkerPortals" | "iptvStalkerUrl" | "iptvStalkerMac"> {
  const first = portals.find((portal) => portal.enabled !== false);
  return { iptvStalkerPortals: portals, iptvStalkerUrl: first?.portalUrl ?? "", iptvStalkerMac: first?.macAddress ?? "" };
}

/** Legacy fields to publish for a portal list (first enabled portal). */
export function legacyStalkerFields(portals: StalkerPortalEntry[]) {
  const { iptvStalkerUrl, iptvStalkerMac } = stalkerPortalsPatch(portals);
  return { stalkerPortalUrl: iptvStalkerUrl, stalkerMacAddress: iptvStalkerMac };
}

export type PortalDraftProblem = "missing" | "bad-url" | "bad-mac";

/** Problems with a portal the user typed, before it is saved or tested. */
export function portalDraftProblem(url: string, mac: string): PortalDraftProblem | null {
  const portalUrl = normalizePortalUrl(url);
  const macAddress = normalizePortalMac(mac);
  if (!portalUrl || !macAddress) return "missing";
  if (!/^https?:\/\/[^/\s]+/i.test(portalUrl)) return "bad-url";
  if (!/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(macAddress)) return "bad-mac";
  return null;
}

/** Add a portal at the end, or replace the one with the same id (its other fields are kept). */
export function upsertStalkerPortal(portals: StalkerPortalEntry[], draft: { id?: string; name: string; portalUrl: string; macAddress: string }): StalkerPortalEntry[] {
  const portalUrl = normalizePortalUrl(draft.portalUrl);
  const macAddress = normalizePortalMac(draft.macAddress);
  const existing = draft.id ? portals.find((portal) => portal.id === draft.id) : undefined;
  if (existing) {
    return portals.map((portal) => portal.id === existing.id
      ? { ...portal, name: draft.name.trim() || portal.name, portalUrl, macAddress }
      : portal);
  }
  const id = nextStalkerPortalId(portals.map((portal) => portal.id));
  if (!id) return portals;
  return [...portals, { id, name: draft.name.trim() || `Portal ${id.replace(/^stalker/, "")}`, portalUrl, macAddress, enabled: true }];
}

/* ---------- channel ids and category keys ---------- */

/** The playlist (or portal) a channel belongs to (StalkerPortalSupport.playlistIdFromChannelId). */
export function channelPlaylistId(channelId: string): string {
  if (channelId.startsWith("stalker:")) {
    const portal = channelId.slice(8).split(":")[0];
    if (portal) return portal;
  }
  return channelId.split(":")[0] || "default";
}

/** `stalker|<group>` → `stalker1|<group>` (StalkerPortalSupport.migrateLegacyPlaylistGroupKey). */
export function migrateLegacyStalkerKey(key: string): string {
  return key.startsWith(`${LEGACY_STALKER_ID}|`) ? `stalker1|${key.slice(LEGACY_STALKER_ID.length + 1)}` : key;
}

export function migrateLegacyStalkerKeys(keys: string[]): string[] {
  return keys.some((key) => key.startsWith(`${LEGACY_STALKER_ID}|`)) ? [...new Set(keys.map(migrateLegacyStalkerKey))] : keys;
}

export function migrateLegacyStalkerKeyMap<T>(map: Record<string, T>): Record<string, T> {
  const keys = Object.keys(map);
  if (!keys.some((key) => key.startsWith(`${LEGACY_STALKER_ID}|`))) return map;
  const next: Record<string, T> = {};
  // A key already written in the new shape wins over its legacy twin.
  for (const key of keys) if (!key.startsWith(`${LEGACY_STALKER_ID}|`)) next[key] = map[key];
  for (const key of keys) if (key.startsWith(`${LEGACY_STALKER_ID}|`)) next[migrateLegacyStalkerKey(key)] ??= map[key];
  return next;
}

/** Category-keyed settings with single-portal Stalker keys moved to Portal 1. */
export function migrateLegacyIptvKeys<T extends Partial<AppSettings>>(settings: T): T {
  const next: Partial<AppSettings> = { ...settings };
  if (Array.isArray(next.hiddenGroupIds)) next.hiddenGroupIds = migrateLegacyStalkerKeys(next.hiddenGroupIds);
  if (Array.isArray(next.lockedIptvGroupIds)) next.lockedIptvGroupIds = migrateLegacyStalkerKeys(next.lockedIptvGroupIds);
  if (Array.isArray(next.groupOrder)) next.groupOrder = migrateLegacyStalkerKeys(next.groupOrder);
  if (Array.isArray(next.favoriteGroupIds)) next.favoriteGroupIds = migrateLegacyStalkerKeys(next.favoriteGroupIds);
  if (next.iptvChannelOrder) next.iptvChannelOrder = migrateLegacyStalkerKeyMap(next.iptvChannelOrder);
  if (next.iptvGroupNames) next.iptvGroupNames = migrateLegacyStalkerKeyMap(next.iptvGroupNames);
  return next as T;
}
