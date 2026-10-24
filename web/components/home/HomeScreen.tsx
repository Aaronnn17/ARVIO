"use client";
import { useTranslation } from "@/lib/i18n";
import { collectionFolders, collectionHomeCatalogs } from "@/lib/collectionPresentation";


import { Info, Play } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { IMDB_LOGO } from "@/lib/serviceLogos";
import { genreNamesFromIds, getCardMeta, getLogoUrl } from "@/lib/tmdb";
import { getImdbRating } from "@/lib/imdbRatings";
import { useApp } from "@/lib/store";
import { useKidsFilter } from "@/lib/useKids";
import { LazyRail } from "@/components/media/LazyRail";
import { CustomCollectionRail } from "@/components/media/CustomCollectionRail";
import { MediaRail } from "@/components/media/MediaRail";
import { FavoriteTvRail } from "@/components/media/FavoriteTvRail";
import { FAVORITE_TV_CATALOG_ID } from "@/lib/favoriteTv";
import type { Category, MediaItem } from "@/lib/types";

export function HomeScreen({ onCollectionOpenChange }: { onCollectionOpenChange?: (open: boolean) => void }) {
  const translateUi = useTranslation();
  const { hero, categories, catalogConfigs, homeServerRows, continueWatching, openDetails, setHeroPreview, settings } = useApp();
  const posterMode = settings.cardLayoutMode === "poster";
  const kids = useKidsFilter();

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

  useEffect(() => () => {
    if (hoverTimer.current) clearTimeout(hoverTimer.current);
  }, []);

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
    const first = row.items.find(kids.allows);
    if (first) {
      seededHero.current = true;
      setHeroPreview(first);
    }
  };

  // Kids profiles rotate only titles rated for the profile.
  const heroPool = useMemo(() => heroPoolRows.filter(kids.allows), [heroPoolRows, kids.allows]);

  // Auto-advance the hero every 8s until the user hovers a card (which pins the
  // hero to whatever they're pointing at and stops the carousel).
  useEffect(() => {
    if (heroPool.length < 2) return undefined;
    let index = 0;
    if (!userInteractedHero.current) setHeroPreview(heroPool[0]);
    const timer = window.setInterval(() => {
      if (userInteractedHero.current) return;
      index = (index + 1) % heroPool.length;
      setHeroPreview(heroPool[index]);
    }, 8000);
    return () => window.clearInterval(timer);
  }, [heroPool, setHeroPreview]);

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

  const onCardFocus = (item: MediaItem) => {
    userInteractedHero.current = true;
    if (hoverTimer.current) clearTimeout(hoverTimer.current);
    hoverTimer.current = setTimeout(() => setHeroPreview(item), 220);
  };

  // The billboard never shows a title the kids filter has not cleared.
  const shownHero = displayHero && kids.allows(displayHero) ? displayHero : null;
  const heroGenres = (shownHero?.genres?.length ? shownHero.genres : genreNamesFromIds(shownHero?.genreIds)).slice(0, 3);

  // Real IMDb rating for the hero (Cinemeta by imdb id) — TMDB's vote_average
  // is a different score and must not sit under an IMDb badge. The imdb id
  // rides along on the cached per-card TMDB call.
  const [heroImdbRating, setHeroImdbRating] = useState<string | null>(null);
  useEffect(() => {
    setHeroImdbRating(null);
    if (!shownHero || shownHero.id <= 0 || shownHero.isHomeServer) return undefined;
    let active = true;
    void (async () => {
      const imdbId = shownHero.imdbId
        ?? (await getCardMeta({ mediaType: shownHero.mediaType, id: shownHero.id }).catch(() => null))?.imdbId;
      if (!active || !imdbId) return;
      const rating = await getImdbRating(shownHero.mediaType, imdbId).catch(() => null);
      if (active && rating) setHeroImdbRating(rating);
    })();
    return () => { active = false; };
  }, [shownHero?.id, shownHero?.mediaType, shownHero?.imdbId, shownHero?.isHomeServer]);
  const metaBits = [
    shownHero?.mediaType === "tv" ? "Series" : "Movie",
    shownHero?.releaseDate?.slice(0, 4) || shownHero?.year || null,
    shownHero?.duration || null,
    ...heroGenres
  ].filter(Boolean);

  return (
    // has-hero mirrors the CSS :has(.hero) padding rule for TV browsers whose
    // engines predate :has() support (Tizen/webOS).
    <div className={shownHero ? "screen has-hero" : "screen"}>
      {shownHero && (
        <section className="hero home-hero" style={{ backgroundImage: shownHero.backdrop ? `url(${shownHero.backdrop})` : undefined }}>
          <div className="hero-copy">
            <div className="hero-title">
              {heroLogo ? (
                <img className="hero-logo" src={heroLogo} alt={shownHero.title} />
              ) : (
                <h2>{shownHero.title}</h2>
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
            <p>
              {(() => {
                const desc = shownHero.overview || shownHero.subtitle || translateUi("Continue from your ARVIO library.");
                return desc.length > 150 ? desc.slice(0, 150) + "..." : desc;
              })()}
            </p>
            <div className="hero-actions">
              <button type="button" className="primary" onClick={() => openDetails(shownHero)}><Play size={20} fill="currentColor" /> {translateUi(" Play")}</button>
              <button type="button" className="secondary" onClick={() => openDetails(shownHero)}><Info size={20} /> {translateUi(" More Info")}</button>
            </div>
          </div>
        </section>
      )}
      {dedupedCategories.map((category) => (
        <MediaRail key={category.id} category={category} onOpen={openDetails} onFocus={onCardFocus} posterMode={posterMode} />
      ))}
      {collectionHomeCatalogs(catalogConfigs).map((catalog, index) => (
        catalog.id === FAVORITE_TV_CATALOG_ID ? (kids.active ? null : <FavoriteTvRail key={catalog.id} title={catalog.name} />) :
        String(catalog.kind).toUpperCase() === "COLLECTION_RAIL" ?
        <CustomCollectionRail key={catalog.id} catalog={catalog} onOpen={openDetails} onCollectionOpenChange={onCollectionOpenChange}
          folders={collectionFolders(catalog, catalogConfigs)} /> :
        <LazyRail
          key={catalog.id}
          catalog={catalog}
          eager={index < 8}
          onOpen={openDetails}
          onFocus={onCardFocus}
          onLoaded={seedHeroFromRow}
        />
      ))}
      {/* Like Android, a catalog list without the row still shows it, after the others. */}
      {!kids.active && !catalogConfigs.some((catalog) => catalog.id === FAVORITE_TV_CATALOG_ID) && <FavoriteTvRail />}
      {homeServerRows.map((category) => (
        <MediaRail key={category.id} category={category} onOpen={openDetails} onFocus={onCardFocus} posterMode={posterMode} />
      ))}
    </div>
  );
}
