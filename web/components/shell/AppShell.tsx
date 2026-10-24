"use client";

import { useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import { useApp } from "@/lib/store";
import { kidsLevelOf } from "@/lib/kids";
import { config } from "@/lib/config";
import { useTranslation } from "@/lib/i18n";
import { focusAfterViewChange, installTvNav } from "@/lib/tvNav";
import { watchHoverCapability } from "@/lib/deviceClass";
import { HomeScreen } from "@/components/home/HomeScreen";
import { ProfileSelectionScreen } from "@/components/profile/ProfileSelectionScreen";
import { HomeScreenTip } from "@/components/player/HomeScreenTip";
import { BackHandler } from "./BackHandler";
import { ExternalPlaybackPrompt } from "./ExternalPlaybackPrompt";
import { MediaContextMenu } from "./MediaContextMenu";
import { NoAddonsPrompt } from "./NoAddonsPrompt";
import { EntitlementGate, PaywallScreen } from "./Paywall";
import { Toast } from "./Toast";
import { TopNav } from "./TopNav";
import { PremiumUsage } from "./PremiumUsage";
import { PartnerLinkHandler } from "./PartnerLinkHandler";
import { ScreenBoundary } from "./ErrorBoundary";
import { OnScreenKeyboard } from "./OnScreenKeyboard";
import { UpdateBanner } from "./UpdateBanner";
import { notifySectionNavigation } from "./UpdateWatcher";
import { XboxControllerTip } from "./XboxControllerTip";
import { OfflineNotice } from "./OfflineNotice";

// Code splitting: Home (the first screen after the profile picker) ships in the
// first-load bundle; every other section, the details page and the player are
// separate chunks fetched on first use. The player chunk (plus hls.js and
// mediabunny) is prefetched once a details page opens or playback starts —
// see PaidPlayerWarmup.

function ScreenLoading() {
  const translateUi = useTranslation();
  return (
    <div className="screen-loading" role="status" aria-label={translateUi("Loading")}>
      <span className="screen-loading-spinner" aria-hidden="true" />
    </div>
  );
}

function PlayerLoading() {
  return <div className="player-loading-shell" aria-hidden="true"><span className="screen-loading-spinner" /></div>;
}

const loadPlayer = () => import("@/components/player/PlayerOverlay");

const SearchScreen = dynamic(() => import("@/components/search/SearchScreen").then((m) => m.SearchScreen), { ssr: false, loading: () => <ScreenLoading /> });
const WatchlistScreen = dynamic(() => import("@/components/watchlist/WatchlistScreen").then((m) => m.WatchlistScreen), { ssr: false, loading: () => <ScreenLoading /> });
const LiveTvScreen = dynamic(() => import("@/components/livetv/LiveTvScreen").then((m) => m.LiveTvScreen), { ssr: false, loading: () => <ScreenLoading /> });
const AddonsScreen = dynamic(() => import("@/components/addons/AddonsScreen").then((m) => m.AddonsScreen), { ssr: false, loading: () => <ScreenLoading /> });
const SettingsScreen = dynamic(() => import("@/components/settings/SettingsScreen").then((m) => m.SettingsScreen), { ssr: false, loading: () => <ScreenLoading /> });
const DetailsDrawer = dynamic(() => import("@/components/details/DetailsDrawer").then((m) => m.DetailsDrawer), { ssr: false, loading: () => <ScreenLoading /> });
const LoginScreen = dynamic(() => import("@/components/login/LoginScreen").then((m) => m.LoginScreen), { ssr: false, loading: () => <ScreenLoading /> });
const PlayerOverlay = dynamic(() => loadPlayer().then((m) => m.PlayerOverlay), { ssr: false, loading: () => <PlayerLoading /> });

const ACCENTS: Record<string, string> = {
  arctic: "#ededed",
  gold: "#ffcd3c",
  green: "#00d588",
  blue: "#3b82f6",
  purple: "#8b5cf6"
};

/**
 * Preload the playback stack (player chunk, hls.js, mediabunny) — but only
 * once someone is heading for playback: a details page opened or Play pressed.
 * Browsing visitors never download it.
 */
function PaidPlayerWarmup({ active }: { active: boolean }) {
  const warmed = useRef(false);
  useEffect(() => {
    if (!active || warmed.current) return undefined;
    warmed.current = true;
    const warm = () => {
      void loadPlayer().catch(() => undefined);
      void import("hls.js").catch(() => undefined);
      void import("mediabunny").catch(() => undefined);
    };
    if (typeof window.requestIdleCallback === "function") {
      const id = window.requestIdleCallback(warm, { timeout: 3000 });
      return () => window.cancelIdleCallback(id);
    }
    const timer = window.setTimeout(warm, 800);
    return () => window.clearTimeout(timer);
  }, [active]);
  return null;
}

/** Overlays that live outside any one screen (all views). */
function ShellOverlays() {
  return (
    <>
      <OnScreenKeyboard />
      <UpdateBanner />
      <XboxControllerTip />
      <OfflineNotice />
    </>
  );
}

export function AppShell() {
  const { auth, goToLogin, signOut, view, section, setSection, settings, selected, activeStream, activeChannel, activeProfile, closePlayer } = useApp();
  const kidsProfile = Boolean(kidsLevelOf(activeProfile));
  // A kids profile never stays on Live TV, however it got there (a saved section, a link).
  useEffect(() => {
    if (kidsProfile && section === "tv") setSection("home");
  }, [kidsProfile, section, setSection]);
  const [mounted, setMounted] = useState(false);
  const [collectionOpen, setCollectionOpen] = useState(false);
  // The player chunk mounts on first playback and then stays mounted (it keeps
  // its own state between streams, as before code splitting).
  const [playerMounted, setPlayerMounted] = useState(false);
  useEffect(() => {
    if (activeStream) setPlayerMounted(true);
  }, [activeStream]);

  useEffect(() => {
    setMounted(true);
  }, []);

  // D-pad / keyboard spatial navigation for TV browsers (Tizen, webOS, Xbox)
  // and desktop keyboards: arrows move focus, Enter activates, TV Back runs
  // the Back ladder. The gamepad layer (HTPC mode: Xbox Ally, Steam Deck, any
  // pad) feeds the same engine, so a controller drives the whole app.
  useEffect(() => {
    installTvNav();
    const stopHoverWatch = watchHoverCapability();
    void import("@/lib/gamepadNav").then((mod) => mod.installGamepadNav()).catch(() => undefined);
    return stopHoverWatch;
  }, []);

  useEffect(() => {
    document.documentElement.style.scrollBehavior = settings.smoothScrolling ? "smooth" : "auto";
  }, [settings.smoothScrolling]);

  // Starting focus after every view change: the control that triggered it
  // usually unmounted, leaving focus on <body> (remotes then had nowhere to
  // start from, and screen readers announced nothing).
  const playerOpen = Boolean(activeStream);
  useEffect(() => {
    if (!mounted || playerOpen) return undefined;
    return focusAfterViewChange();
  }, [mounted, view, section, selected?.id, selected?.mediaType, playerOpen]);

  // Switching top-level sections is a safe moment for a pending app update.
  const previousSection = useRef(section);
  useEffect(() => {
    if (previousSection.current === section) return undefined;
    previousSection.current = section;
    // After BackHandler has written the new route, so the reload lands here.
    const timer = window.setTimeout(notifySectionNavigation, 0);
    return () => window.clearTimeout(timer);
  }, [section]);

  if (!mounted) {
    return (
      <main className="app-boot">
        <img src="/arvio-logo.svg" alt="" className="app-boot-logo" />
        <img src="/arvio-wordmark.svg" alt="ARVIO" className="app-boot-wordmark" />
      </main>
    );
  }

  // Show the product before requesting a login. After signing in, the app
  // opens in explore mode (see EntitlementGate).
  if (config.paywallEnabled && !auth) {
    return <><PaywallScreen state={null} accountId={null} isSignedIn={false} onEntitled={() => {}} onConnect={goToLogin} onSignOut={signOut} /><ShellOverlays /></>;
  }
  if (view === "login") return <><ScreenBoundary screen="login"><LoginScreen /></ScreenBoundary><ShellOverlays /></>;

  const accent = ACCENTS[settings.accentColor] ?? ACCENTS.arctic;

  // Explore mode: signed-in accounts use the app; the gate asks for Premium
  // only when something would play. Self-hosted builds and the Android app
  // remain unchanged.
  return (
    <EntitlementGate>
    <PaidPlayerWarmup active={Boolean(selected) || Boolean(activeStream)} />
    {view === "profiles" ? <ScreenBoundary screen="profiles"><ProfileSelectionScreen /></ScreenBoundary> :
    <main
      className={`app-shell ${settings.oledBlack ? "oled" : ""} ${settings.spoilerBlur ? "spoiler-blur" : ""}`}
      style={{ ["--accent" as string]: accent }}
    >
      {(!activeStream || (section === "tv" && activeChannel)) && <TopNav />}
      <PartnerLinkHandler />

      <section className="content">
        {section === "home" && (!selected || collectionOpen) && (
          <div hidden={Boolean(selected)}>
            <ScreenBoundary screen="home"><NoAddonsPrompt /><HomeScreen onCollectionOpenChange={setCollectionOpen} /></ScreenBoundary>
          </div>
        )}
        {selected ? (
          <ScreenBoundary screen="details" resetKey={`${selected.mediaType}:${selected.id}`}><DetailsDrawer /></ScreenBoundary>
        ) : (
          <>
            {section === "search" && <ScreenBoundary screen="search"><SearchScreen /></ScreenBoundary>}
            {section === "watchlist" && <ScreenBoundary screen="library"><WatchlistScreen /></ScreenBoundary>}
            {section === "tv" && !kidsProfile && <ScreenBoundary screen="tv"><LiveTvScreen /></ScreenBoundary>}
            {section === "addons" && <ScreenBoundary screen="addons"><AddonsScreen /></ScreenBoundary>}
            {section === "settings" && <ScreenBoundary screen="settings"><SettingsScreen /></ScreenBoundary>}
          </>
        )}
      </section>

      {playerMounted ? (
        <ScreenBoundary screen="player" resetKey={activeStream?.url} overlay onDismiss={closePlayer}><PlayerOverlay /></ScreenBoundary>
      ) : (
        // Before the first playback the player chunk is not loaded; the
        // Add-to-Home-Screen tip it normally hosts renders on its own.
        <HomeScreenTip playerOpen={false} />
      )}
      <ExternalPlaybackPrompt />
      <MediaContextMenu />
      <PremiumUsage />
      <BackHandler />
      <Toast />
    </main>
    }
    <ShellOverlays />
    </EntitlementGate>
  );
}
