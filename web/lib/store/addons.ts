// App store (lib/store.tsx): Installing, removing and enabling addons, and loading one catalog row.
import { queueAddons, flushAddonOutbox } from "../addonOutbox";
import { useCallback } from "react";
import { installAddon as installAddonManifest, loadLocalAddons, normalizeAddons, saveLocalAddons } from "../addons";
import { AddonAlreadyInstalledError, addonInstanceId, addonManifestId, applyAddonInstall, duplicateAddons, isSameInstall, type AddonInstallMode } from "../addonInstall";
import { loadCatalog } from "../tmdb";
import type { InstalledAddon, CatalogConfig } from "../types";
import { authClient } from "./clients";
import type { useUpdateSettings } from "./settingsSync";
import type { StoreCore } from "./core";

export function useAddonActions(store: StoreCore & Pick<ReturnType<typeof useUpdateSettings>, "updateSettings">) {
  const { activeProfileId, addonsRef, setAddons, settings, settingsRef, updateSettings } = store;
  const persistAddons = useCallback(async (next: InstalledAddon[], options: { removedIds?: string[]; addedIds?: string[]; onLocalSave?: () => void } = {}) => {
    const normalized = normalizeAddons(next);
    queueAddons(authClient, normalized, activeProfileId, options.removedIds, options.addedIds);
    saveLocalAddons(normalized);
    if (!authClient.session && JSON.stringify(loadLocalAddons()) !== JSON.stringify(normalized)) throw new Error("Device storage is full. Keep this page open and retry saving.");
    addonsRef.current = normalized;
    setAddons(normalized);
    options.onLocalSave?.();
    // Cloud writes are union-based; a removal must be an explicit id list so the
    // shared library can never be shrunk by a stale/partial in-memory view.
    try { await flushAddonOutbox(authClient); }
    catch { throw new Error("Addons saved on this device. Cloud sync is pending and will retry automatically."); }
  }, [activeProfileId]);

  const loadCatalogRow = useCallback((catalog: CatalogConfig) => loadCatalog(catalog, settings.language, addonsRef.current, settingsRef.current.homeServers), [settings.language]);

  // An addon that is already installed (same manifest id or link) is never
  // replaced silently: without a mode this throws AddonAlreadyInstalledError
  // and the Addons screen asks "Replace / Keep both" (Android parity).
  const installAddon = useCallback(async (source: string | InstalledAddon, options: { mode?: AddonInstallMode } = {}) => {
    const fetched = typeof source === "string" ? await installAddonManifest(source) : source;
    const current = addonsRef.current;
    const existing = duplicateAddons(current, fetched);
    if (existing.length && !options.mode) throw new AddonAlreadyInstalledError(fetched, existing);
    let candidate = fetched;
    if (existing.length && options.mode === "keep-both") {
      if (isSameInstall(current, fetched)) throw new Error("This exact addon link is already installed.");
      candidate = { ...fetched, id: await addonInstanceId(addonManifestId(fetched), fetched.manifestUrl) };
    }
    const { next, removedIds } = applyAddonInstall(current, candidate, existing.length && options.mode ? options.mode : "new");
    await persistAddons(next, { addedIds: [candidate.id], removedIds });
    return candidate;
  }, [persistAddons]);

  const removeAddon = useCallback(async (addon: InstalledAddon) => {
    const next = addonsRef.current.filter((candidate) => candidate.id !== addon.id);
    await persistAddons(next, { removedIds: [addon.id] });
  }, [persistAddons]);

  const setAddonsState = useCallback(async (next: InstalledAddon[]) => {
    await persistAddons(next, { onLocalSave: () => updateSettings({
      disabledAddonIds: next.filter((addon) => addon.enabled === false).map((addon) => addon.id)
    }) });
  }, [persistAddons, updateSettings]);
  return { persistAddons, loadCatalogRow, installAddon, removeAddon, setAddonsState };
}
