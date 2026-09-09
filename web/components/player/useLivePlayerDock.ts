"use client";

import { useEffect, useState, type CSSProperties } from "react";

/** Reposition the existing player, never mount a second video/connection for preview. */
export function useLivePlayerDock(enabled: boolean, identity: string, onClose: () => void) {
  const [bounds, setBounds] = useState<CSSProperties>();
  const [expanded, setExpanded] = useState(false);
  useEffect(() => setExpanded(false), [identity]);
  useEffect(() => {
    if (!enabled) { setBounds(undefined); return; }
    let slot: HTMLElement | null = null;
    let attached = false;
    let frame = 0;
    const measure = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        if (!slot?.isConnected) return;
        const r = slot.getBoundingClientRect();
        setBounds({ position: "fixed", inset: "auto", left: r.left, top: r.top, width: r.width, height: r.height });
      });
    };
    const resize = new ResizeObserver(measure);
    const discover = () => {
      if (slot?.isConnected) return;
      const next = document.getElementById("live-tv-player-dock");
      if (!next && attached) { onClose(); return; }
      if (!next) return;
      slot = next; attached = true; resize.observe(slot); measure();
    };
    const mutations = new MutationObserver(discover);
    mutations.observe(document.body, { childList: true, subtree: true });
    window.addEventListener("scroll", measure, true);
    window.addEventListener("resize", measure);
    discover();
    return () => {
      resize.disconnect(); mutations.disconnect(); cancelAnimationFrame(frame);
      window.removeEventListener("scroll", measure, true); window.removeEventListener("resize", measure);
    };
  }, [enabled, identity, onClose]);
  return { docked: enabled && Boolean(bounds) && !expanded, canDock: enabled && Boolean(bounds),
    style: enabled && !expanded ? bounds : undefined, expand: () => setExpanded(true), collapse: () => setExpanded(false) };
}
