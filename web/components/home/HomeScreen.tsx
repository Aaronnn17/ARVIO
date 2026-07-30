"use client";

import { Info, Play } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { IMDB_LOGO } from "@/lib/serviceLogos";
import { genreNamesFromIds, getCardMeta, getLogoUrl } from "@/lib/tmdb";
import { getImdbRating } from "@/lib/imdbRatings";
import { useApp } from "@/lib/store";
import { LazyRail } from "@/components/media/LazyRail";
import { MediaRail } from "@/components/media/MediaRail";
import type { Category, MediaItem } from "@/lib/types";

export function HomeScreen() {
  const { hero, categories, catalogConfigs, homeServerRows, continueWatching, openDetails, setHeroPreview, settings } = useApp();
  const posterMode = settings.cardLayoutMode === "poster";

  // The eager rails (trending/popular/provider lists) overlap heavily; keep each
  // title in the first rail it appears in and trim repeats from later rails,
  // unless doing so would hollow a rail out.
  const dedupedCategories = useMemo(() => {
    const seen = new Set<string>();
    return categories.map((category) => {
      const kept = category.items.filter((item) => !seen.has(`${item.mediaType}-${item.id}`));
      const items = kept.length >= Math.min(8, category.items.length) ? kept : category.items;
      items.forEach((item) => seen.add(`${item.mediaType}-${item.id}`));
      return items === category.items ? category : { ...category, items };
    });
  }, [categories]);
  const [heroLogo, setHeroLogo] = useState<string | null>(null);
  const [displayHero, setDisplayHero] = useState<MediaItem | null>(null);
  const hoverTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const seededHero = useRef(false);
  const userInteractedHero = useRef(false);

  // Showcase titles for the rotating hero, collected from the first rails as
  // they load (trending rails arrive lazily, so we accumulate here).
  const [heroPoolRows, setHeroPoolRows] = useState<MediaItem[]>([]);

  const seedHeroFromRow = (row: Category) => {
    // Feed the first couple of catalog rows into the hero rotation pool.
    setHeroPoolRows((prev) => {
      if (prev.length >= 12) return prev;
      const seen = new Set(prev.map((i) => `${i.mediaType}-${i.id}`));
      const additions = row.items
        .filter((item) => item.backdrop && !seen.has(`${item.mediaType}-${item.id}`))
        .slice(0, 8);
      return additions.length ? [...prev, ...additions].slice(0, 12) : prev;
    });
    if (seededHero.current || continueWatching.length) return;
    const first = row.items[0];
    if (first) {
      seededHero.current = true;
      setHeroPreview(first);
    }
  };

  const heroPool = heroPoolRows;
  const [heroIndex, setHeroIndex] = useState(0);
  const [heroPaused, setHeroPaused] = useState(false);
  const touchStartX = useRef<number | null>(null);

  const handleHeroTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
  };

  const handleHeroTouchEnd = (e: React.TouchEvent) => {
    if (touchStartX.current === null || heroPool.length < 2) return;
    const dx = e.changedTouches[0].clientX - touchStartX.current;
    const threshold = 50;
    if (dx < -threshold) {
      setHeroIndex((prev) => (prev + 1) % heroPool.length);
    } else if (dx > threshold) {
      setHeroIndex((prev) => (prev - 1 + heroPool.length) % heroPool.length);
    }
    touchStartX.current = null;
  };

  // Auto-advance hero carousel every 6.5 seconds unless hovered directly
  useEffect(() => {
    if (heroPool.length < 2 || heroPaused) return undefined;
    const timer = window.setInterval(() => {
      setHeroIndex((prev) => (prev + 1) % heroPool.length);
    }, 6500);
    return () => window.clearInterval(timer);
  }, [heroPool.length, heroPaused]);

  useEffect(() => {
    if (heroPool[heroIndex]) {
      setHeroPreview(heroPool[heroIndex]);
    }
  }, [heroIndex, heroPool, setHeroPreview]);

  // Synchronize hero changes so all content (logo, text, metadata, backdrop) updates together.
  useEffect(() => {
    if (!hero) {
      setDisplayHero(null);
      setHeroLogo(null);
      return;
    }

    let active = true;

    // Fast path: if no hero is currently displayed, show it immediately so there is no blank screen on first load
    if (!displayHero) {
      setDisplayHero(hero);
      void getLogoUrl({ mediaType: hero.mediaType, id: hero.id })
        .then((url) => {
          if (active) setHeroLogo(url);
        })
        .catch(() => undefined);
      return;
    }

    // Normal path: fetch the logo in the background first, then swap all content together
    void getLogoUrl({ mediaType: hero.mediaType, id: hero.id })
      .then((url) => {
        if (!active) return;
        setHeroLogo(url);
        setDisplayHero(hero);
      })
      .catch(() => {
        if (!active) return;
        setHeroLogo(null);
        setDisplayHero(hero);
      });

    return () => {
      active = false;
    };
  }, [hero, displayHero]);

  const heroGenres = (displayHero?.genres?.length ? displayHero.genres : genreNamesFromIds(displayHero?.genreIds)).slice(0, 3);

  // Real IMDb rating for the hero (Cinemeta by imdb id) — TMDB's vote_average
  // is a different score and must not sit under an IMDb badge. The imdb id
  // rides along on the cached per-card TMDB call.
  const [heroImdbRating, setHeroImdbRating] = useState<string | null>(null);
  useEffect(() => {
    setHeroImdbRating(null);
    if (!displayHero || displayHero.id <= 0 || displayHero.isHomeServer) return undefined;
    let active = true;
    void (async () => {
      const imdbId = displayHero.imdbId
        ?? (await getCardMeta({ mediaType: displayHero.mediaType, id: displayHero.id }).catch(() => null))?.imdbId;
      if (!active || !imdbId) return;
      const rating = await getImdbRating(displayHero.mediaType, imdbId).catch(() => null);
      if (active && rating) setHeroImdbRating(rating);
    })();
    return () => { active = false; };
  }, [displayHero?.id, displayHero?.mediaType, displayHero?.imdbId, displayHero?.isHomeServer]);
  const metaBits = [
    displayHero?.mediaType === "tv" ? "Series" : "Movie",
    displayHero?.releaseDate?.slice(0, 4) || displayHero?.year || null,
    displayHero?.duration || null,
    ...heroGenres
  ].filter(Boolean);

  return (
    <div className="screen">
      {displayHero && (
        <section
          className="hero"
          style={{ backgroundImage: displayHero.backdrop ? `url(${displayHero.backdrop})` : undefined }}
          onMouseEnter={() => setHeroPaused(true)}
          onMouseLeave={() => setHeroPaused(false)}
          onTouchStart={handleHeroTouchStart}
          onTouchEnd={handleHeroTouchEnd}
        >
          <div className="hero-copy" key={displayHero.id}>
            <div className="hero-title-slot">
              {heroLogo ? (
                <img className="hero-logo" src={heroLogo} alt={displayHero.title} />
              ) : (
                <h2>{displayHero.title}</h2>
              )}
            </div>
            <div className="hero-meta">
              {heroImdbRating && (
                <span className="hero-imdb">
                  <img src={IMDB_LOGO} alt="IMDb" />
                  <b>{heroImdbRating}</b>
                </span>
              )}
              {metaBits.map((bit) => <span key={String(bit)}>{bit}</span>)}
            </div>
            <p className="hero-overview">
              {displayHero.overview || displayHero.subtitle || "Continue from your ARVIO library."}
            </p>
            <div className="hero-actions">
              <button type="button" className="primary" onClick={() => openDetails(displayHero)}><Play size={20} fill="currentColor" /> Play</button>
              <button type="button" className="secondary" onClick={() => openDetails(displayHero)}><Info size={20} /> More Info</button>
            </div>
          </div>
          {heroPool.length > 1 && (
            <div className="hero-carousel-dots" aria-label="Featured content carousel">
              {heroPool.map((item, idx) => (
                <button
                  key={`${item.mediaType}-${item.id}-${idx}`}
                  type="button"
                  className={`hero-dot ${idx === heroIndex ? "is-active" : ""}`}
                  onClick={() => setHeroIndex(idx)}
                  aria-label={`Slide ${idx + 1}: ${item.title}`}
                />
              ))}
            </div>
          )}
        </section>
      )}
      {dedupedCategories.map((category) => (
        <MediaRail key={category.id} category={category} onOpen={openDetails} posterMode={posterMode} />
      ))}
      {homeServerRows.map((category) => (
        <MediaRail key={category.id} category={category} onOpen={openDetails} posterMode={posterMode} />
      ))}
      {catalogConfigs.map((catalog, index) => (
        <LazyRail
          key={catalog.id}
          catalog={catalog}
          eager={index < 8}
          onOpen={openDetails}
          onLoaded={seedHeroFromRow}
        />
      ))}
    </div>
  );
}
