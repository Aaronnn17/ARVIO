"use client";
import { ArrowDown, ArrowUp, Download, Eye, EyeOff, Plus, RefreshCw, RotateCcw, Search, Trash2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { defaultCatalogs, isDefaultCollection, mergeCatalogs, setDefaultCollectionsEnabled, updateHiddenCatalogIds } from "@/lib/catalogs";
import { parseCustomCollections, mergeImportedCollections } from "@/lib/customCollections";
import { loadSimklCustomList, parseSimklListUrl, searchSimklCustomLists, type SimklCustomList } from "@/lib/simklLists";
import { textRequest, proxiedUrl } from "@/lib/http";
import { buildHomeServerCatalogConfigs } from "@/lib/homeserver";
import { iptvPlaylistSignature } from "@/lib/iptv";
import { useApp } from "@/lib/store";
import type { AppSettings, CatalogConfig, HomeServerConfig, IptvPlaylistEntry } from "@/lib/types";
import { IptvGroupSettings } from "../IptvGroupSettings";
import { Empty, Group, Row, SecretInput, Segmented, Select, SectionHeader, Status, TextInput, Toggle, fallbackId, safeArray } from "../ui";

/* ---------- Addons ---------- */

export function AddonsSection() {
  const translateUi = useTranslation();
  const { addons, installAddon, removeAddon, setAddonsState, setToast } = useApp();
  const [addonUrl, setAddonUrl] = useState("");
  const [installing, setInstalling] = useState(false);
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
  return (
    <>
      <SectionHeader title="Addons" description="Stremio-compatible addons supply catalogs, sources and subtitles. Addons are shared by every profile and every ARVIO app on your account." />
      <Group title="Install an addon">
        <div className="st-form">
          <input className="st-input" value={addonUrl} onChange={(e) => setAddonUrl(e.target.value)} placeholder="https://addon.example.com/manifest.json"
            aria-label={translateUi("Addon manifest URL")} inputMode="url" onKeyDown={(e) => { if (e.key === "Enter") void install(); }} />
          <div className="st-form-actions">
            <button type="button" className="st-btn is-primary" disabled={installing} onClick={() => void install()}><Plus size={16} /> {translateUi(installing ? "Installing..." : "Install")}</button>
          </div>
        </div>
      </Group>
      <Group title={`${translateUi("Installed")} · ${addons.length}`}>
        {addons.length === 0 ? <Empty>{translateUi("Install Stremio-compatible addons by URL above.")}</Empty> : (
          <ul className="st-list">
            {safeArray(addons).map((addon, index) => {
              const resources = safeArray(addon.resources);
              const addonCatalogs = safeArray(addon.catalogs);
              const has = (resource: string) => resources.length === 0 || resources.some((item) => typeof item === "string" ? item === resource : item?.name === resource);
              const tags = [has("stream") ? "Sources" : "", has("subtitles") ? "Subtitles" : "", addonCatalogs.length ? `${addonCatalogs.length} catalogs` : ""].filter(Boolean);
              const off = addon.enabled === false;
              return (
                <li className={`st-item ${off ? "is-off" : ""}`} key={fallbackId("addon", index, addon.id || addon.manifestUrl)}>
                  <div className="st-item-main">
                    <span className="st-item-title"><span>{addon.name || translateUi("Unnamed addon")}</span><span className="st-tag">v{addon.version || "1.0.0"}</span></span>
                    <span className="st-item-sub" title={addon.manifestUrl}>{tags.map((tag) => translateUi(tag)).join(" · ") || translateUi("Manifest")} · {addon.manifestUrl}</span>
                  </div>
                  <div className="st-item-actions">
                    <Toggle label={`${addon.name || "addon"}`} value={!off}
                      onChange={() => setAddonsState(addons.map((a) => a.id === addon.id ? { ...a, enabled: a.enabled === false } : a)).catch((error) => setToast(error instanceof Error ? error.message : "Could not save addons."))} />
                    <button type="button" className="st-icon-btn is-danger" aria-label={translateUi("Remove {value0}", { value0: addon.name || "addon" })}
                      onClick={() => void removeAddon(addon).catch((error) => setToast(error instanceof Error ? error.message : "Could not remove addon."))}><Trash2 size={17} /></button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </Group>
    </>
  );
}

/* ---------- Catalogs (Home rows) ---------- */

export function CatalogsSection() {
  const translateUi = useTranslation();
  const { settings, updateSettings, setToast, activeProfile } = useApp();
  const standardCatalogs = mergeCatalogs(safeArray(settings.catalogs), safeArray(settings.hiddenCatalogIds), safeArray(settings.hiddenAddonCatalogIds))
    .filter((catalog) => catalog.sourceType !== "home-server");
  const [homeServerCatalogs, setHomeServerCatalogs] = useState<CatalogConfig[]>([]);
  const [customCatalogUrl, setCustomCatalogUrl] = useState("");
  const [simklQuery, setSimklQuery] = useState("");
  const [simklResults, setSimklResults] = useState<SimklCustomList[]>([]);
  const [catalogBusy, setCatalogBusy] = useState(false);
  const [collectionsInput, setCollectionsInput] = useState("");
  const [importingCollections, setImportingCollections] = useState(false);
  useEffect(() => { setSimklResults([]); setSimklQuery(""); }, [activeProfile?.id]);
  const catalogs = [...homeServerCatalogs, ...standardCatalogs];
  const currentImportTarget = useRef({ profileId: activeProfile?.id, catalogs });
  currentImportTarget.current = { profileId: activeProfile?.id, catalogs };
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);

  useEffect(() => {
    let cancelled = false;
    void buildHomeServerCatalogConfigs(safeArray(settings.homeServers), safeArray(settings.catalogs), safeArray(settings.hiddenHomeServerCatalogIds))
      .then((next) => { if (!cancelled) setHomeServerCatalogs(next); })
      .catch(() => { if (!cancelled) setHomeServerCatalogs([]); });
    return () => { cancelled = true; };
  }, [settings.catalogs, settings.hiddenHomeServerCatalogIds, settings.homeServers]);

  const updateCatalogs = (next: CatalogConfig[], hiddenIds = settings.hiddenCatalogIds) => {
    const homeServer = next.filter((catalog) => catalog.sourceType === "home-server");
    const standard = next.filter((catalog) => catalog.sourceType !== "home-server");
    updateSettings({
      catalogs: next,
      hiddenCatalogIds: updateHiddenCatalogIds(standard, hiddenIds),
      hiddenAddonCatalogIds: updateHiddenCatalogIds(standard.filter((catalog) => catalog.sourceType === "addon"), settings.hiddenAddonCatalogIds),
      hiddenHomeServerCatalogIds: updateHiddenCatalogIds(homeServer, settings.hiddenHomeServerCatalogIds),
    });
  };
  const moveCatalog = (id: string, offset: number) => {
    const index = catalogs.findIndex((c) => c.id === id);
    const target = index + offset;
    if (index < 0 || target < 0 || target >= catalogs.length) return;
    const next = [...catalogs];
    const [moved] = next.splice(index, 1);
    next.splice(target, 0, moved);
    updateCatalogs(next);
  };

  const addSimklCatalog = async (rawUrl: string) => {
    const simkl = parseSimklListUrl(rawUrl);
    if (!simkl || catalogBusy) return;
    const profile = activeProfile?.id;
    setCatalogBusy(true);
    try {
      if (catalogs.some((c) => c.sourceType === "simkl" && c.sourceUrl && parseSimklListUrl(c.sourceUrl)?.id === simkl.id)) throw new Error("This catalogue is already added.");
      const list = await loadSimklCustomList(simkl.url);
      if (!mounted.current || currentImportTarget.current.profileId !== profile) return;
      const latest = currentImportTarget.current.catalogs;
      if (latest.some((c) => c.sourceType === "simkl" && c.sourceUrl && parseSimklListUrl(c.sourceUrl)?.id === simkl.id)) throw new Error("This catalogue is already added.");
      updateCatalogs([{ id: `custom_${crypto.randomUUID()}`, name: list.name, sourceType: "simkl", sourceUrl: simkl.url,
        sourceRef: `simkl_list:${simkl.id}`, mediaType: list.media_type === "movies" ? "movie" : "tv", enabled: true }, ...latest]);
      setCustomCatalogUrl("");
    } catch (error) {
      if (mounted.current && currentImportTarget.current.profileId === profile) setToast((error as Error).message);
    } finally {
      if (mounted.current) setCatalogBusy(false);
    }
  };

  const addList = async () => {
    if (catalogBusy) return;
    if (!customCatalogUrl.trim()) { setToast("Enter a catalog URL first."); return; }
    const simkl = parseSimklListUrl(customCatalogUrl);
    if (simkl) { await addSimklCatalog(simkl.url); return; }
    updateCatalogs([{ id: `custom_${crypto.randomUUID()}`, name: "Custom MDBList", sourceType: "mdblist", mediaType: "all", sourceUrl: customCatalogUrl.trim(), enabled: true }, ...catalogs]);
    setCustomCatalogUrl("");
  };

  const importCollections = async () => {
    const profileId = activeProfile?.id;
    setImportingCollections(true);
    try {
      const input = collectionsInput.trim();
      const raw = input.startsWith("[") || input.startsWith("{");
      if (!raw && !/^https?:\/\//i.test(input)) throw new Error("Enter an HTTP(S) URL or collections JSON");
      const json = raw ? input : await textRequest(proxiedUrl(input));
      const imported = await parseCustomCollections(json, raw ? undefined : input);
      if (!mounted.current || currentImportTarget.current.profileId !== profileId) return;
      updateCatalogs(mergeImportedCollections(currentImportTarget.current.catalogs, imported));
      setCollectionsInput("");
      setToast("Collections imported");
    } catch (error) {
      setToast(error instanceof Error ? error.message : "Could not import collections");
    } finally {
      setImportingCollections(false);
    }
  };

  const shown = catalogs.filter((c) => c.enabled).length;
  const collectionPacks = Array.from(new Map(catalogs.filter((c) => c.packId?.startsWith("usercol_")).map((c) => [c.packId!, c.packName || c.name])).entries());
  const hasDefaultCollections = catalogs.some((c) => isDefaultCollection(c) && c.kind === "COLLECTION_RAIL");

  return (
    <>
      <SectionHeader title="Home rows" description="The rows on your Home screen, in order. Changes apply to this profile on every ARVIO app.">
        <button type="button" className="st-btn" onClick={() => updateCatalogs([...homeServerCatalogs, ...defaultCatalogs])}><RotateCcw size={16} /> {translateUi("Reset")}</button>
      </SectionHeader>

      <Group title={`${translateUi("Rows")} · ${shown}/${catalogs.length} ${translateUi("shown")}`}>
        <ul className="st-list">
          {catalogs.map((catalog, index) => (
            <li className={`st-item ${catalog.enabled ? "" : "is-off"}`} key={fallbackId("catalog", index, catalog.id)}>
              <div className="st-item-main">
                <input className="st-input is-wide" aria-label={translateUi("Row name")} value={catalog.name}
                  onChange={(e) => updateCatalogs(catalogs.map((c) => c.id === catalog.id ? { ...c, name: e.target.value } : c))} />
                <span className="st-item-sub">{(catalog.sourceType || "custom").toUpperCase()}{(catalog.sourceUrl || catalog.endpoint || catalog.addonCatalogId) ? ` · ${catalog.sourceUrl || catalog.endpoint || catalog.addonCatalogId}` : ""}</span>
              </div>
              <div className="st-item-actions">
                <Segmented label="Card style" value={catalog.layout ?? "landscape"} options={[["landscape", "Wide"], ["poster", "Poster"]]}
                  onChange={(layout) => updateCatalogs(catalogs.map((c) => c.id === catalog.id ? { ...c, layout } : c))} />
                <button type="button" className="st-icon-btn" disabled={index === 0} onClick={() => moveCatalog(catalog.id, -1)} aria-label={translateUi("Move {value0} up", { value0: catalog.name })}><ArrowUp size={17} /></button>
                <button type="button" className="st-icon-btn" disabled={index === catalogs.length - 1} onClick={() => moveCatalog(catalog.id, 1)} aria-label={translateUi("Move {value0} down", { value0: catalog.name })}><ArrowDown size={17} /></button>
                <button type="button" className="st-icon-btn" aria-label={`${catalog.enabled ? translateUi("Hide") : translateUi("Show")} ${catalog.name}`}
                  onClick={() => updateCatalogs(catalogs.map((c) => c.id === catalog.id ? { ...c, enabled: !c.enabled } : c))}>
                  {catalog.enabled ? <Eye size={17} /> : <EyeOff size={17} />}
                </button>
                {!catalog.isPreinstalled && catalog.sourceType !== "home-server" && (
                  <button type="button" className="st-icon-btn is-danger" aria-label={translateUi("Remove {value0}", { value0: catalog.name })}
                    onClick={() => updateCatalogs(catalogs.filter((c) => c.id !== catalog.id))}><Trash2 size={17} /></button>
                )}
              </div>
            </li>
          ))}
        </ul>
      </Group>

      <Group title="Add a list" description="Paste a Trakt, MDBList or SIMKL list URL. SIMKL custom-list contents require SIMKL PRO or VIP.">
        <div className="st-form">
          <input className="st-input" value={customCatalogUrl} onChange={(e) => setCustomCatalogUrl(e.target.value)} placeholder="Trakt / MDBList / SIMKL list URL"
            aria-label={translateUi("List URL")} onKeyDown={(e) => { if (e.key === "Enter") void addList(); }} />
          <div className="st-form-actions"><button type="button" className="st-btn is-primary" disabled={catalogBusy} onClick={() => void addList()}><Plus size={16} /> {translateUi("Add")}</button></div>
        </div>
        <div className="st-form">
          <input className="st-input" value={simklQuery} onChange={(event) => setSimklQuery(event.target.value)} placeholder={translateUi("Search SIMKL lists")} aria-label={translateUi("Search SIMKL lists")} />
          <div className="st-form-actions">
            <button type="button" className="st-btn" disabled={catalogBusy || simklQuery.trim().length < 2} onClick={async () => {
              const profile = activeProfile?.id;
              setCatalogBusy(true);
              try {
                const results = await searchSimklCustomLists(simklQuery);
                if (mounted.current && currentImportTarget.current.profileId === profile) setSimklResults(results);
              } catch (error) {
                if (mounted.current && currentImportTarget.current.profileId === profile) setToast((error as Error).message);
              } finally {
                if (mounted.current) setCatalogBusy(false);
              }
            }}><Search size={16} /> {translateUi("Search")}</button>
          </div>
        </div>
        {simklResults.length > 0 && (
          <ul className="st-list">
            {simklResults.map((list) => (
              <li className="st-item" key={list.id}>
                <div className="st-item-main"><span className="st-item-title"><span>{list.name}</span></span><span className="st-item-sub">SIMKL · {list.counts?.items ?? "—"}</span></div>
                <button type="button" className="st-btn" disabled={catalogBusy || catalogs.some((c) => c.sourceRef === `simkl_list:${list.id}`)}
                  onClick={() => void addSimklCatalog(list.user?.id ? `https://simkl.com/${list.user.id}/list/${list.id}` : `https://simkl.com/lists/${list.id}`)}>{translateUi("Add")}</button>
              </li>
            ))}
          </ul>
        )}
      </Group>

      <Group title="Collections" description="Import a collections pack from a URL or paste its JSON.">
        {hasDefaultCollections && (
          <Row id="default-collections" label="Default collections" scope="all">
            <Toggle label="Default collections" value={catalogs.some((c) => isDefaultCollection(c) && c.kind === "COLLECTION_RAIL" && c.enabled)}
              onChange={(enabled) => { const next = setDefaultCollectionsEnabled(catalogs, settings.hiddenCatalogIds, enabled); updateCatalogs(next.catalogs, next.hiddenIds); }} />
          </Row>
        )}
        {collectionPacks.length > 0 && (
          <ul className="st-list">
            {collectionPacks.map(([id, name]) => (
              <li className="st-item" key={id}>
                <div className="st-item-main"><span className="st-item-title"><span>{name}</span></span></div>
                <button type="button" className="st-icon-btn is-danger" aria-label={`${translateUi("Remove")} ${name}`} onClick={() => updateCatalogs(catalogs.filter((c) => c.packId !== id))}><Trash2 size={17} /></button>
              </li>
            ))}
          </ul>
        )}
        <div className="st-form">
          <textarea className="st-input" aria-label={translateUi("Collection")} value={collectionsInput} onChange={(e) => setCollectionsInput(e.target.value)} placeholder={translateUi("Collections URL or JSON")} rows={3} />
          <div className="st-form-actions">
            <button type="button" className="st-btn" disabled={importingCollections || !collectionsInput.trim()} onClick={() => void importCollections()}>
              <Download size={16} /> {translateUi(importingCollections ? "Importing..." : "Import collections")}
            </button>
          </div>
        </div>
      </Group>
    </>
  );
}

/* ---------- Live TV (IPTV) ---------- */

export function LiveTvSection() {
  const translateUi = useTranslation();
  const { settings, updateSettings, refreshIptv, setToast, busy, iptvSnapshot, activeProfile, auth } = useApp();
  const activeProfileId = activeProfile?.id;
  const groupScope = `${auth?.userId ?? "local"}:${activeProfileId ?? "local"}`;
  const playlistSignature = iptvPlaylistSignature(settings.iptvPlaylists) + (settings.iptvStalkerUrl ? JSON.stringify([settings.iptvStalkerUrl, settings.iptvStalkerMac]) : "");
  const groupsLoaded = iptvSnapshot.scopeKey === groupScope && iptvSnapshot.signature === playlistSignature;
  useEffect(() => {
    if (!groupsLoaded && (settings.iptvPlaylists.length || settings.iptvStalkerUrl)) void refreshIptv();
  }, [groupScope, playlistSignature, groupsLoaded, refreshIptv, settings.iptvPlaylists.length]);
  const [name, setName] = useState("");
  const [m3uUrl, setM3uUrl] = useState("");
  const [epgUrl, setEpgUrl] = useState("");
  const playlists = safeArray(settings.iptvPlaylists);
  const updatePlaylists = (next: IptvPlaylistEntry[]) => updateSettings({ iptvPlaylists: next });
  const isLoadingTv = Boolean(busy && busy.toLowerCase().includes("tv"));
  const channelCount = groupsLoaded ? (iptvSnapshot.allChannels ?? iptvSnapshot.channels ?? []).length : 0;

  const addPlaylist = () => {
    const trimmedM3u = m3uUrl.trim();
    const trimmedEpg = epgUrl.trim();
    if (!trimmedM3u) { setToast("Enter an M3U playlist URL first."); return; }
    if (!/^https?:\/\//i.test(trimmedM3u)) { setToast("Playlist URL must start with http:// or https://."); return; }
    if (trimmedEpg && !/^https?:\/\//i.test(trimmedEpg)) { setToast("EPG URL must start with http:// or https://."); return; }
    updatePlaylists([{ id: crypto.randomUUID(), name: name.trim() || "IPTV Playlist", m3uUrl: trimmedM3u, epgUrl: trimmedEpg, enabled: true }, ...playlists]);
    setName(""); setM3uUrl(""); setEpgUrl("");
    setToast("IPTV playlist saved.");
  };
  const edit = (id: string, patch: Partial<IptvPlaylistEntry>) => updatePlaylists(playlists.map((item) => item.id === id ? { ...item, ...patch } : item));

  return (
    <>
      <SectionHeader title="Live TV" description="IPTV playlists, programme guides and portals for this profile. They sync to the Live TV page on every ARVIO app.">
        <button type="button" className="st-btn" disabled={isLoadingTv} onClick={() => void refreshIptv()}>
          <RefreshCw size={16} className={isLoadingTv ? "spin" : undefined} /> {translateUi(isLoadingTv ? "Refreshing..." : "Refresh channels")}
        </button>
      </SectionHeader>

      <Group title={`${translateUi("Playlists")} · ${playlists.length}`} description={groupsLoaded && channelCount ? translateUi("{value0} channels loaded.", { value0: channelCount.toLocaleString() }) : undefined}>
        {playlists.length === 0 ? <Empty>{translateUi("No IPTV playlists configured.")}</Empty> : (
          <ul className="st-list">
            {playlists.map((playlist, index) => (
              <li className={`st-item ${playlist.enabled ? "" : "is-off"}`} key={fallbackId("playlist", index, playlist.id)}>
                <div className="st-item-main">
                  <input className="st-input is-wide" aria-label={translateUi("Playlist name")} value={playlist.name} onChange={(e) => edit(playlist.id, { name: e.target.value })} />
                  <input className="st-input is-wide" aria-label={translateUi("M3U playlist URL")} value={playlist.m3uUrl} onChange={(e) => edit(playlist.id, { m3uUrl: e.target.value })} />
                  <input className="st-input is-wide" aria-label={translateUi("EPG URL")} placeholder={translateUi("EPG XMLTV URL (optional)")} value={playlist.epgUrl ?? ""} onChange={(e) => edit(playlist.id, { epgUrl: e.target.value })} />
                </div>
                <div className="st-item-actions">
                  <Toggle label={playlist.name} value={playlist.enabled} onChange={(enabled) => edit(playlist.id, { enabled })} />
                  <button type="button" className="st-icon-btn is-danger" aria-label={translateUi("Remove {value0}", { value0: playlist.name })} onClick={() => updatePlaylists(playlists.filter((item) => item.id !== playlist.id))}><Trash2 size={17} /></button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </Group>

      <Group title="Add a playlist">
        <div className="st-form">
          <input className="st-input" value={name} onChange={(e) => setName(e.target.value)} placeholder={translateUi("Playlist name")} aria-label={translateUi("Playlist name")} />
          <input className="st-input" value={m3uUrl} onChange={(e) => setM3uUrl(e.target.value)} placeholder={translateUi("M3U playlist URL")} aria-label={translateUi("M3U playlist URL")} inputMode="url" />
          <input className="st-input" value={epgUrl} onChange={(e) => setEpgUrl(e.target.value)} placeholder={translateUi("EPG XMLTV URL (optional)")} aria-label={translateUi("EPG XMLTV URL (optional)")} inputMode="url" />
          <div className="st-form-actions"><button type="button" className="st-btn is-primary" onClick={addPlaylist}><Plus size={16} /> {translateUi("Add playlist")}</button></div>
        </div>
      </Group>

      <Group title="Channel list">
        <Row id="iptv-sort" label="Sort order" hint="How live channels and groups are ordered." scope="all">
          <Select label="Sort order" value={settings.iptvSortOrder ?? "provider"} onChange={(v) => updateSettings({ iptvSortOrder: v as "provider" | "number" | "name" })}
            options={[["provider", "Provider order"], ["number", "Channel number"], ["name", "Alphabetical (A-Z)"]]} />
        </Row>
        <Row id="iptv-favorites-home" label="Favorite channels on Home" hint="Pin your starred channels to the top of Home." scope="all">
          <Toggle label="Favorite channels on Home" value={settings.iptvFavoritesOnHome !== false} onChange={(v) => updateSettings({ iptvFavoritesOnHome: v })} />
        </Row>
        <Row id="guide-rows" label="Guide rows" hint="Channel rows shown in the TV guide." scope="android">
          <Select label="Guide rows" value={String(settings.guideRowCount ?? 0)} onChange={(v) => updateSettings({ guideRowCount: Number(v) })}
            options={[["0", "Automatic"], ["6", "6"], ["7", "7"], ["8", "8"], ["9", "9"], ["10", "10"]]} />
        </Row>
      </Group>

      {playlists.length > 0 && (
        <Group title="Categories" description="Show, hide and reorder channel groups.">
          <div style={{ padding: "4px 20px 16px" }}>
            <IptvGroupSettings key={groupScope} settings={settings} updateSettings={updateSettings} channels={groupsLoaded ? iptvSnapshot.allChannels ?? iptvSnapshot.channels : []} />
          </div>
        </Group>
      )}

      <Group title="Stalker portal" description="For providers that give you a portal address and a MAC address instead of a playlist.">
        <Row id="stalker-url" label="Portal URL" scope="all" stack>
          <TextInput label="Stalker portal URL" wide value={settings.iptvStalkerUrl} onChange={(v) => updateSettings({ iptvStalkerUrl: v })} placeholder="http://portal.example.com/c/" inputMode="url" />
        </Row>
        <Row id="stalker-mac" label="MAC address" scope="all" stack>
          <TextInput label="Stalker MAC address" wide value={settings.iptvStalkerMac} onChange={(v) => updateSettings({ iptvStalkerMac: v })} placeholder="00:1A:79:00:00:00" />
        </Row>
      </Group>
    </>
  );
}

/* ---------- Home server ---------- */

export function HomeServerSection() {
  const translateUi = useTranslation();
  const { settings, updateSettings, setToast } = useApp();
  const [type, setType] = useState<HomeServerConfig["type"]>("jellyfin");
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [token, setToken] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [testing, setTesting] = useState(false);
  const [adding, setAdding] = useState(false);
  const servers = safeArray(settings.homeServers);
  const update = (next: HomeServerConfig[]) => updateSettings({ homeServers: next });

  const buildDraft = (): HomeServerConfig => ({
    id: crypto.randomUUID(), type, name: name.trim() || type, url: url.trim(),
    token: token.trim() || undefined, username: username.trim() || undefined, password: password || undefined, enabled: true,
  });
  const validate = () => {
    if (!url.trim()) { setToast("Enter a Home Server URL first."); return false; }
    if (type === "plex" && !token.trim()) { setToast("Plex needs an access token (X-Plex-Token)."); return false; }
    return true;
  };
  const testConnection = async () => {
    if (!validate()) return;
    setTesting(true);
    try {
      const { testHomeServerConnection } = await import("@/lib/homeserver");
      const result = await testHomeServerConnection(buildDraft());
      setToast(result.ok ? `Connected to ${result.serverName || "server"}${result.libraryCount ? ` — ${result.libraryCount} libraries` : ""}.` : `Could not connect: ${result.error}`);
    } catch (error) {
      setToast(error instanceof Error ? error.message : "Connection test failed.");
    } finally {
      setTesting(false);
    }
  };
  const addConnection = async () => {
    if (!validate()) return;
    setAdding(true);
    try {
      const { testHomeServerConnection } = await import("@/lib/homeserver");
      const result = await testHomeServerConnection(buildDraft());
      if (!result.ok || !result.connection) { setToast(`Could not connect: ${result.error || "Connection failed"}`); return; }
      update([result.connection, ...servers]);
      setName(""); setUrl(""); setToken(""); setUsername(""); setPassword("");
      setToast(`Connected to ${result.serverName || result.connection.name} and saved ${result.libraryCount ?? 0} libraries.`);
    } catch (error) {
      setToast(error instanceof Error ? error.message : "Connection failed.");
    } finally {
      setAdding(false);
    }
  };

  return (
    <>
      <SectionHeader title="Home server" description="Connect Plex, Jellyfin or Emby. Matching movies and episodes appear as sources, and the connection syncs to this profile on your other ARVIO apps." />
      <Group title={`${translateUi("Servers")} · ${servers.length}`}>
        {servers.length === 0 ? <Empty>{translateUi("No home servers configured.")}</Empty> : (
          <ul className="st-list">
            {servers.map((server, index) => (
              <li className={`st-item ${server.enabled ? "" : "is-off"}`} key={fallbackId("server", index, server.id)}>
                <div className="st-item-main">
                  <span className="st-item-title"><span>{server.name || server.type || translateUi("Home server")}</span><span className="st-tag">{server.type || "server"}</span></span>
                  <span className="st-item-sub">{server.url || translateUi("No URL")}</span>
                </div>
                <div className="st-item-actions">
                  <Toggle label={server.name || "server"} value={server.enabled} onChange={() => update(servers.map((s) => s.id === server.id ? { ...s, enabled: !s.enabled } : s))} />
                  <button type="button" className="st-icon-btn is-danger" aria-label={translateUi("Remove {value0}", { value0: server.name || "server" })} onClick={() => update(servers.filter((s) => s.id !== server.id))}><Trash2 size={17} /></button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </Group>
      <Group title="Add a server" description={type === "plex" ? "Plex needs an access token (X-Plex-Token)." : type === "jellyfin" ? "Use an API token or a username and password. Silo: use the Jellyfin-compatible address. Optional profile: username#ProfileName. Protected profile: password#PIN." : "Use an API token or a username and password."}>
        <div className="st-tabs">
          <Segmented label="Server type" value={type} onChange={setType} options={[["jellyfin", "Jellyfin / Silo"], ["emby", "Emby"], ["plex", "Plex"]]} />
        </div>
        <div className="st-form">
          <input className="st-input" value={name} onChange={(e) => setName(e.target.value)} placeholder={translateUi("Name")} aria-label={translateUi("Name")} />
          <input className="st-input" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://server:8096" aria-label={translateUi("Server address")} inputMode="url" />
          <input className="st-input" value={token} onChange={(e) => setToken(e.target.value)} aria-label={translateUi("Access token")} autoComplete="off"
            placeholder={type === "plex" ? translateUi("X-Plex-Token (required)") : translateUi("API token (optional)")} />
          {type !== "plex" && <input className="st-input" value={username} onChange={(e) => setUsername(e.target.value)} placeholder={translateUi("Username (optional)")} aria-label={translateUi("Username")} autoComplete="off" />}
          {type !== "plex" && <input className="st-input" value={password} onChange={(e) => setPassword(e.target.value)} placeholder={translateUi("Password")} aria-label={translateUi("Password")} type="password" autoComplete="new-password" />}
          <div className="st-form-actions">
            <button type="button" className="st-btn" disabled={testing} onClick={() => void testConnection()}>{translateUi(testing ? "Testing…" : "Test")}</button>
            <button type="button" className="st-btn is-primary" disabled={adding || testing} onClick={() => void addConnection()}><Plus size={16} /> {translateUi(adding ? "Connecting…" : "Add")}</button>
          </div>
        </div>
      </Group>
    </>
  );
}

/* ---------- Metadata & keys ---------- */

export function MetadataSection() {
  const translateUi = useTranslation();
  const { settings, updateSettings: set } = useApp();
  const chain = (value: string[] | undefined, fallback: string[]) => (value?.length ? value : fallback).map((p) => p.toUpperCase()).join(" → ");
  const tvdbActive = Boolean(settings.customTvdbApiKey?.trim());
  return (
    <>
      <SectionHeader title="Metadata and keys" description="Bring your own TMDB or TVDB key if you have one. Keys stay in this browser and are never uploaded." />
      <Group title="Your API keys">
        <Row id="tmdb-key" label="TMDB API key" hint="Custom v3 API key for TMDB requests. Leave empty to use ARVIO's." scope="browser" stack>
          <SecretInput label="TMDB API key" value={settings.customTmdbApiKey || ""} placeholder="System Default Key" onChange={(v) => set({ customTmdbApiKey: v })} />
        </Row>
        <Row id="tvdb-key" label="TVDB v4 API key" hint={tvdbActive ? "Active — TVDB enabled for metadata fallback" : "TVDB is disabled until a custom API key is provided"} scope="browser" stack>
          <SecretInput label="TVDB v4 API key" value={settings.customTvdbApiKey || ""} placeholder="Enter Custom TVDB Key to Enable" onChange={(v) => set({ customTvdbApiKey: v })} />
        </Row>
        <Row id="tvdb-pin" label="TVDB user PIN" hint="Required if using subscriber user key" scope="browser" stack>
          <SecretInput label="TVDB user PIN" value={settings.customTvdbUserPin || ""} placeholder="Optional User PIN" onChange={(v) => set({ customTvdbUserPin: v })} />
        </Row>
      </Group>
      <Group title="Where details come from" description="ARVIO asks these sources in order and uses the first good match.">
        <Row label="Anime"><Status tone="off">{chain(settings.metadataAnimeProviders, ["anilist", "tvdb", "tmdb"])}</Status></Row>
        <Row label="TV shows"><Status tone="off">{chain(settings.metadataTvProviders, ["tvdb", "tmdb"])}</Status></Row>
        <Row label="Movies"><Status tone="off">{chain(settings.metadataMovieProviders, ["tmdb"])}</Status></Row>
      </Group>
      {!tvdbActive && <p className="st-row-hint">{translateUi("Without a TVDB key, TV shows use TMDB.")}</p>}
    </>
  );
}

