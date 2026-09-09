"use client";

import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { X, Tv, PanelLeft, ChevronRight, Play, RefreshCw } from "lucide-react";
import { guideSports, isOnAir, availableEventChannels, sportsGuideRows, type SportsGuideEvent } from "@/lib/sportsGuide";
import type { InstalledAddon, IptvChannel, IptvNowNext } from "@/lib/types";
import { attachSportsArtwork, loadSportsGuideArtwork, type SportsEventArtwork } from "@/lib/sportsArtwork";
import { VirtualList } from "@/components/ui/VirtualList";

const NO_ADDONS: InstalledAddon[] = [];
export function SportsGuidePane({ channels, guide, onPlay, onEnter, onOpenCategories, providerNames = {}, addons = NO_ADDONS }: {
  channels: IptvChannel[]; guide: Record<string, IptvNowNext>;
  onPlay: (channel: IptvChannel) => void; onEnter: () => void; onOpenCategories: () => void;
  providerNames?: Record<string, string>;
  addons?: InstalledAddon[];
}) {
  const [artwork, setArtwork] = useState<SportsEventArtwork[]>([]);
  useEffect(() => {
    let active = true;
    setArtwork([]);
    const load = () => void loadSportsGuideArtwork(addons).then(items => { if (active) setArtwork(items); });
    load();
    const refresh = setInterval(load, 600_000);
    return () => { active = false; clearInterval(refresh); };
  }, [addons]);
  const [events, setEvents] = useState<SportsGuideEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [retry, setRetry] = useState(0);
  const [now, setNow] = useState(Date.now);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const origin = useRef<HTMLButtonElement | null>(null);
  const root = useRef<HTMLElement>(null);
  const entered = useRef(false);
  useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 30_000); return () => clearInterval(timer); }, []);
  const scanDay = new Date(now).toDateString();
  useEffect(() => {
    setLoading(true);
    setFailed(false);
    // Only send channels with cached schedules, not the entire 100k-channel playlist.
    const worker = new Worker(new URL("./sportsGuide.worker.ts", import.meta.url));
    worker.onmessage = (event: MessageEvent<SportsGuideEvent[]>) => {
      setEvents(previous => { const rank = new Map(previous.map((e, i) => [e.id, i])); return event.data.sort((a, b) => (rank.get(a.id) ?? Infinity) - (rank.get(b.id) ?? Infinity)); });
      setLoading(false);
    };
    worker.onerror = () => { setFailed(true); setLoading(false); };
    worker.postMessage({ channels: channels.filter((ch) => Boolean(guide[ch.id])), guide, now: Date.now() });
    return () => worker.terminate();
  }, [channels, guide, scanDay, retry]);
  const accessibleIds = useMemo(() => new Set(channels.map((ch) => ch.id)), [channels]);
  // Hide revoked/hidden sources immediately, including during a worker refresh.
  const visibleEvents = useMemo(() => events.map((event) => ({ ...event, channels: event.channels.filter((ch) => accessibleIds.has(ch.id)),
    schedules: event.schedules ? Object.fromEntries(Object.entries(event.schedules).filter(([id]) => accessibleIds.has(id))) : undefined }))
    .filter((event) => event.channels.length && Object.values(event.schedules ?? { fallback: event.programme }).some(p => p.endUtcMillis > now)), [events, accessibleIds, now]);
  const illustratedEvents = useMemo(() => attachSportsArtwork(visibleEvents, artwork), [visibleEvents, artwork]);
  const rows = useMemo(() => sportsGuideRows(illustratedEvents, now), [illustratedEvents, now]);
  useEffect(() => {
    if (!rows.length || entered.current) return;
    entered.current = true;
    root.current?.querySelector<HTMLButtonElement>(".tv-event-card")?.focus({ preventScroll: true });
  }, [rows.length]);
  const selected = illustratedEvents.find((event) => event.id === selectedId);
  const sourceChannels = selected ? (isOnAir(selected, now) ? availableEventChannels(selected, now) : selected.channels) : [];
  const close = () => { dialog.current?.close(); setSelectedId(null); origin.current?.focus({ preventScroll: true }); };
  useEffect(() => {
    if (!selectedId || dialog.current?.open) return;
    dialog.current?.showModal();
    // Virtual rows appear after ResizeObserver measures the opened dialog.
    const observer = new MutationObserver(() => focusFirst());
    const focusFirst = () => {
      const first = dialog.current?.querySelector<HTMLButtonElement>(".tv-event-source:not(:disabled)");
      if (first) { first.focus({ preventScroll: true }); observer.disconnect(); }
      return Boolean(first);
    };
    if (!focusFirst() && dialog.current) observer.observe(dialog.current, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, [selectedId]);
  const stamp = (event: SportsGuideEvent) => {
    if (isOnAir(event, now)) return "ON AIR";
    const date = new Date(event.programme.startUtcMillis);
    const today = new Date(now), tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1);
    const day = date.toDateString() === today.toDateString() ? "Today" : date.toDateString() === tomorrow.toDateString() ? "Tomorrow" : new Intl.DateTimeFormat([], { weekday: "short", day: "numeric", month: "short" }).format(date);
    return `${day} ${new Intl.DateTimeFormat([], { hour: "numeric", minute: "2-digit" }).format(date)}`;
  };
  return <section ref={root} className="tv-sports" aria-label="Sports">
    <h2><button className="tv-sports-drawer" type="button" aria-label="Categories" onClick={onOpenCategories}><PanelLeft size={22} /></button>Sports</h2>
    {!rows.length && <div className="tv-sports-empty" role="status"><Tv size={32} /><p>{loading ? "Reading sports schedule" : failed ? "Schedule unavailable" : "No sports events in the available guide"}</p>
      {failed && <button type="button" className="secondary" onClick={() => setRetry(value => value + 1)}><RefreshCw size={18} />Retry</button>}
      <button type="button" className="secondary" onClick={onOpenCategories}><PanelLeft size={18} />Categories</button></div>}
    {rows.map((row, rowIndex) => <section className={`tv-sports-section${row.id === "more" ? " is-compact" : ""}`} key={row.id} aria-label={row.title}>
      <div className="tv-sports-row-heading"><h3>{row.title}</h3></div>
      <div className="tv-sports-row">{row.events.map((event, index) => {
        const sport = guideSports.find((s) => s.id === event.sportId)!;
        return <button type="button" className="tv-event-card" key={event.id} onFocus={onEnter}
          onKeyDown={(key) => {
            if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(key.key)) return;
            key.preventDefault(); key.stopPropagation();
            const rtl = getComputedStyle(key.currentTarget).direction === "rtl";
            const backward = key.key === (rtl ? "ArrowRight" : "ArrowLeft");
            const horizontal = key.key === "ArrowLeft" || key.key === "ArrowRight";
            if (horizontal && backward && index === 0) { onOpenCategories(); return; }
            const nextRow = horizontal ? rowIndex : rowIndex + (key.key === "ArrowUp" ? -1 : 1);
            const section = root.current?.querySelectorAll(".tv-sports-row")[nextRow];
            const cards = section?.querySelectorAll<HTMLButtonElement>(".tv-event-card");
            const nextIndex = horizontal ? index + (backward ? -1 : 1) : Math.min(index, (cards?.length ?? 1) - 1);
            const next = cards?.[nextIndex];
            next?.focus({ preventScroll: true });
            next?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" });
          }}
          onClick={(click) => { origin.current = click.currentTarget; setSelectedId(event.id); }}>
          <div className="tv-event-art"><EventArtwork event={event} /><span className={`tv-event-stamp${isOnAir(event, now) ? " is-on-air" : ""}`}>{stamp(event)}</span></div>
          <strong>{event.title}</strong><small className="tv-event-meta"><span className="tv-event-competition">{[sport.title, event.competition].filter(Boolean).join(" · ")}</span>{isOnAir(event, now) && <span><Tv size={16} />{channelCount(availableEventChannels(event, now).length)}</span>}</small>
        </button>;
      })}</div>
    </section>)}
    <dialog ref={dialog} className="tv-event-picker" style={{ "--source-count": Math.max(1, sourceChannels.length) } as CSSProperties}
      onCancel={(event) => { event.preventDefault(); close(); }} onClick={(event) => { if (event.target === event.currentTarget) close(); }}>
      <header>{selected && <div className="tv-event-picker-art"><EventArtwork event={selected} /></div>}<div><p>{selected ? `${stamp(selected)} · ${guideSports.find(s => s.id === selected.sportId)!.title}` : "This event is no longer in the available guide."}</p><h2>{selected?.title ?? "Schedule changed"}</h2></div><button type="button" onClick={close} aria-label="Close"><X /></button></header>
      <h3>{selected && isOnAir(selected, now) ? "Available channels" : "Scheduled channels"}<span>{channelCount(sourceChannels.length)}</span></h3>
      <VirtualList items={sourceChannels} estimate={72} itemKey={(ch) => ch.id} label="Available channels" renderItem={(ch) =>
        <button type="button" className="tv-event-source" disabled={!selected || !isOnAir(selected, now)} onClick={() => {
          if (selected && availableEventChannels(selected, Date.now()).some(channel => channel.id === ch.id)) { close(); onPlay(ch); }
        }}>{ch.logo ? <img src={ch.logo} alt="" /> : <span className="tv-source-logo-fallback"><Tv size={28} /></span>}<span><strong>{ch.name}</strong><small>{providerNames[ch.id.split(":")[0]] || ch.group}</small></span>{ch.qualityLabel && <em>{ch.qualityLabel}</em>}{ch.language && <em>{ch.language.toUpperCase()}</em>}<ChevronRight className="tv-source-arrow" size={22} /><Play className="tv-source-play" size={22} /></button>} />
    </dialog>
  </section>;
}

const channelCount = (count: number) => `${count} ${count === 1 ? "channel" : "channels"}`;

function EventArtwork({ event }: { event: SportsGuideEvent }) {
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null);
  const loaded = Boolean(event.artwork) && loadedUrl === event.artwork;
  const sport = guideSports.find(s => s.id === event.sportId)!;
  return <div className="tv-event-image">
    {!loaded && <div className="tv-event-fallback"><img src={`/images/sports/${sport.asset}.webp`} alt="" loading="lazy" decoding="async" /><span>{event.title}</span></div>}
    {event.artwork && <img src={event.artwork} alt="" loading="lazy" decoding="async" style={{ opacity: loaded ? 1 : 0 }} onLoad={() => setLoadedUrl(event.artwork!)} onError={() => setLoadedUrl(null)} />}
  </div>;
}
