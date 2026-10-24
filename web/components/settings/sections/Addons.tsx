"use client";
// Addons and source priority. The addon order decides which addon's catalogs
// and sources come first; on Android the same order is written into the
// source-priority list (streamProvidersCustomOrder) so the TV follows it.

import { Plus, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { moveIndex } from "@/lib/ordering";
import {
  addonServesStreams, effectiveProviderOrder, integrationOrder, knownProviders, parseIdList,
  providerOrderForAddons, resortProviderOrder, serializeIdList, type IntegrationType, type SourceProvider,
} from "@/lib/sourceOrder";
import { useApp } from "@/lib/store";
import type { InstalledAddon } from "@/lib/types";
import { SortableList } from "../SortableList";
import { Empty, Group, ScopeBadge, SectionHeader, Toggle, safeArray } from "../ui";

function addonTags(addon: InstalledAddon) {
  const resources = safeArray(addon.resources);
  const has = (resource: string) => resources.length === 0 || resources.some((item) => typeof item === "string" ? item === resource : item?.name === resource);
  const catalogs = safeArray(addon.catalogs);
  return [has("stream") ? "Sources" : "", has("subtitles") ? "Subtitles" : "", catalogs.length ? `${catalogs.length} catalogs` : ""].filter(Boolean);
}

export function AddonsSection() {
  const translateUi = useTranslation();
  const { addons, installAddon, removeAddon, setAddonsState, setToast, settings, updateSettings } = useApp();
  const [addonUrl, setAddonUrl] = useState("");
  const [installing, setInstalling] = useState(false);
  const list = safeArray(addons);

  const providers = useMemo(() => knownProviders({
    homeServers: settings.homeServers,
    addons: list,
    pluginRepositories: settings.androidPluginRepositories,
    playlists: settings.iptvPlaylists,
    existingOrder: parseIdList(settings.streamProvidersCustomOrder),
  }), [settings.homeServers, list, settings.androidPluginRepositories, settings.iptvPlaylists, settings.streamProvidersCustomOrder]);
  const ordered = useMemo(() => effectiveProviderOrder(providers, settings.streamProvidersCustomOrder, settings.streamIntegrationsMacroOrder),
    [providers, settings.streamProvidersCustomOrder, settings.streamIntegrationsMacroOrder]);
  const macro = integrationOrder(settings.streamIntegrationsMacroOrder);
  const macroEnabled = settings.streamMacroEnabledMap ?? {};
  const providerEnabled = settings.streamProviderEnabledMap ?? {};

  const integrationLabel = (type: IntegrationType) => ({
    home_server: translateUi("Home server"), stremio_addons: translateUi("Stremio addons"), plugins: translateUi("Plugins"),
    telegram: translateUi("Telegram"), iptv_vod: translateUi("IPTV movies and series"),
  })[type];
  const saveAddons = (next: InstalledAddon[]) => setAddonsState(next).catch((error) => setToast(error instanceof Error ? error.message : "Could not save addons."));

  const install = async () => {
    const trimmedUrl = addonUrl.trim();
    if (!trimmedUrl) { setToast("Enter an addon manifest URL first."); return; }
    if (!/^https?:\/\/.+\/manifest\.json(?:[?#].*)?$/i.test(trimmedUrl)) { setToast("Addon URL must be a full http(s) manifest.json URL."); return; }
    setInstalling(true);
    try {
      await installAddon(trimmedUrl);
      setAddonUrl("");
      setToast("Addon installed.");
    } catch (error) {
      setToast(error instanceof Error ? error.message : "Could not install addon.");
    } finally {
      setInstalling(false);
    }
  };

  // Addon order → web addon list (merge-protected path) + the TV's provider order.
  const moveAddon = (from: number, to: number) => {
    const next = moveIndex(list, from, to);
    if (next === list) return;
    updateSettings({ streamProvidersCustomOrder: providerOrderForAddons(providers, settings.streamProvidersCustomOrder, settings.streamIntegrationsMacroOrder, next.map((addon) => addon.id)) });
    void saveAddons(next);
  };

  const toggleAddon = (addon: InstalledAddon) => {
    const enabled = addon.enabled === false;
    if (addonServesStreams(addon)) updateSettings({ streamProviderEnabledMap: { ...providerEnabled, [`stremio:${addon.id}`]: enabled } });
    void saveAddons(list.map((item) => item.id === addon.id ? { ...item, enabled } : item));
  };

  const moveIntegration = (from: number, to: number) => {
    const next = moveIndex(macro, from, to);
    if (next === macro) return;
    updateSettings({
      streamIntegrationsMacroOrder: serializeIdList(next),
      streamProvidersCustomOrder: resortProviderOrder(settings.streamProvidersCustomOrder, next),
    });
  };

  const moveProvider = (from: number, to: number) => {
    const next = moveIndex(ordered, from, to);
    if (next === ordered) return;
    updateSettings({ streamProvidersCustomOrder: serializeIdList(next.map((item) => item.id)) });
    // Keep the addon list in the same relative order, so web and TV agree.
    const stremio = next.filter((item) => item.type === "stremio_addons").map((item) => item.id.slice("stremio:".length));
    const rank = new Map(stremio.map((id, index) => [id, index]));
    const reordered = [...list].sort((a, b) => (rank.get(a.id) ?? Number.MAX_SAFE_INTEGER) - (rank.get(b.id) ?? Number.MAX_SAFE_INTEGER));
    if (reordered.some((addon, index) => addon.id !== list[index]?.id)) void saveAddons(reordered);
  };

  const providerOn = (item: SourceProvider) => {
    if (macroEnabled[item.type] === false) return false;
    if (item.id in providerEnabled) return providerEnabled[item.id];
    if (item.type === "stremio_addons") return list.find((addon) => `stremio:${addon.id}` === item.id)?.enabled !== false;
    if (item.type === "home_server") return settings.homeServers.find((server) => `homeserver:${server.id}` === item.id)?.enabled !== false;
    if (item.type === "iptv_vod") return settings.iptvPlaylists.find((playlist) => `iptv_playlist:${playlist.id}` === item.id)?.enabled !== false;
    return true;
  };

  return (
    <>
      <SectionHeader title="Addons" description="Stremio-compatible addons supply catalogs, sources and subtitles. Addons are shared by every profile and every ARVIO app on your account." />
      <Group title="Install an addon">
        <div className="st-form">
          <input className="st-input" value={addonUrl} onChange={(e) => setAddonUrl(e.target.value)} placeholder="https://addon.example.com/manifest.json"
            aria-label={translateUi("Addon manifest URL")} inputMode="url" onKeyDown={(e) => { if (e.key === "Enter") void install(); }} />
          <div className="st-form-actions">
            <button type="button" className="st-btn is-primary" disabled={installing} onClick={() => void install()}><Plus size={16} /> {(installing ? translateUi("Installing...") : translateUi("Install"))}</button>
          </div>
        </div>
      </Group>

      <Group title={`${translateUi("Installed")} · ${list.length}`}
        description={<>{translateUi("Addons higher in the list come first: their catalogs, sources and subtitles are used before the ones below.")} <ScopeBadge scope="all" /></>}>
        {list.length === 0 ? <Empty>{translateUi("Install Stremio-compatible addons by URL above.")}</Empty> : (
          <SortableList
            items={list}
            label={translateUi("Installed addons")}
            getKey={(addon) => addon.id || addon.manifestUrl}
            getLabel={(addon) => addon.name || addon.id}
            onMove={moveAddon}
            rowClassName={(addon) => addon.enabled === false ? "is-off" : ""}
            renderMain={(addon) => (
              <>
                <span className="st-sort-title"><span className="st-sort-name">{addon.name || translateUi("Unnamed addon")}</span><span className="st-tag">v{addon.version || "1.0.0"}</span></span>
                <span className="st-sort-sub" title={addon.manifestUrl}>{addonTags(addon).map((tag) => translateUi(tag)).join(" · ") || translateUi("Manifest")} · {addon.manifestUrl}</span>
              </>
            )}
            renderActions={(addon) => (
              <>
                <Toggle label={addon.name || "addon"} value={addon.enabled !== false} onChange={() => toggleAddon(addon)} />
                <button type="button" className="st-icon-btn is-danger" aria-label={translateUi("Remove {value0}", { value0: addon.name || "addon" })}
                  onClick={() => void removeAddon(addon).catch((error) => setToast(error instanceof Error ? error.message : "Could not remove addon."))}><Trash2 size={17} /></button>
              </>
            )}
          />
        )}
      </Group>

      <Group title={translateUi("Source priority")}
        description={<>{translateUi("The order the Android and TV app searches for sources in. Turn a source off here to skip it without uninstalling it.")} <ScopeBadge scope="android" /></>}>
        <div className="st-subhead"><h4>{translateUi("Source types")}</h4></div>
        <SortableList
          items={macro}
          label={translateUi("Source types")}
          getKey={(type) => type}
          getLabel={(type) => integrationLabel(type)}
          onMove={moveIntegration}
          edgeButtons={false}
          rowClassName={(type) => macroEnabled[type] === false ? "is-off" : ""}
          renderMain={(type: IntegrationType) => <span className="st-sort-title"><span className="st-sort-name">{integrationLabel(type)}</span></span>}
          renderActions={(type: IntegrationType) => (
            <Toggle label={integrationLabel(type)} value={macroEnabled[type] !== false}
              onChange={(value) => updateSettings({ streamMacroEnabledMap: { ...macroEnabled, [type]: value } })} />
          )}
        />
        <div className="st-subhead"><h4>{translateUi("Every source")}</h4></div>
        <p className="st-hint">{translateUi("Fine-tune single sources. Reordering here sets a custom order that the TV uses instead of the source types above.")}</p>
        <SortableList
          items={ordered}
          label={translateUi("Sources")}
          getKey={(item) => item.id}
          getLabel={(item) => item.label}
          onMove={moveProvider}
          rowClassName={(item) => providerOn(item) ? "" : "is-off"}
          renderMain={(item) => (
            <>
              <span className="st-sort-title"><span className="st-sort-name">{item.label}</span><span className="st-tag">{integrationLabel(item.type)}</span></span>
              {item.detail && <span className="st-sort-sub">{item.detail === "On your TV" ? translateUi("On your TV") : item.detail}</span>}
            </>
          )}
          renderActions={(item) => (
            <Toggle label={item.label} value={providerOn(item)} disabled={macroEnabled[item.type] === false}
              onChange={(value) => updateSettings({ streamProviderEnabledMap: { ...providerEnabled, [item.id]: value } })} />
          )}
        />
      </Group>
    </>
  );
}
