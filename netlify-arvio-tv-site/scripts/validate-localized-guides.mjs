import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const baseUrl = "https://arvio.tv";
const roots = ["pt-br", "es"];
const errors = [];
const pages = [];

function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(target);
    if (entry.isFile() && entry.name === "index.html") pages.push(target);
  }
}

for (const root of roots) walk(path.join(siteRoot, root));

const routeForFile = (file) => `/${path.relative(siteRoot, path.dirname(file)).replaceAll("\\", "/")}/`;
const knownRoutes = new Set(pages.map(routeForFile));
knownRoutes.add("/");
knownRoutes.add("/guides/");
for (const directory of [
  "android-tv-media-hub", "jellyfin-android-tv", "plex-emby-jellyfin",
  "debrid-usenet-android-tv", "trakt-simkl-sync", "live-tv-epg",
  "ai-subtitles-android-tv", "fire-tv-media-player", "arvio-web"
]) knownRoutes.add(`/${directory}/`);

for (const file of pages) {
  const html = fs.readFileSync(file, "utf8");
  const route = routeForFile(file);
  const expectedCanonical = `${baseUrl}${route}`;
  const canonical = html.match(/<link rel="canonical" href="([^"]+)"/u)?.[1];
  if (canonical !== expectedCanonical) errors.push(`${route}: expected canonical ${expectedCanonical}, got ${canonical}`);

  for (const hreflang of ["en", "pt-BR", "es", "x-default"]) {
    if (!html.includes(`hreflang="${hreflang}"`)) errors.push(`${route}: missing hreflang ${hreflang}`);
  }

  const jsonBlocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/gu)];
  if (!jsonBlocks.length) errors.push(`${route}: missing JSON-LD`);
  for (const [, json] of jsonBlocks) {
    try { JSON.parse(json); } catch (error) { errors.push(`${route}: invalid JSON-LD (${error.message})`); }
  }

  const links = [...html.matchAll(/href="(\/[^"]*)"/gu)].map((match) => match[1]);
  for (const href of links) {
    if (href.startsWith("/assets/") || href.endsWith(".css") || href.startsWith("/go/") || href === "/privacy") continue;
    const cleanRoute = href.split(/[?#]/u)[0];
    if (!knownRoutes.has(cleanRoute)) errors.push(`${route}: internal link does not resolve locally (${href})`);
  }
}

const sitemap = fs.readFileSync(path.join(siteRoot, "sitemap.xml"), "utf8");
const sitemapUrls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/gu)].map((match) => match[1]);
if (sitemapUrls.length !== 33) errors.push(`sitemap: expected 33 URLs, got ${sitemapUrls.length}`);
for (const file of pages) {
  const url = `${baseUrl}${routeForFile(file)}`;
  if (!sitemapUrls.includes(url)) errors.push(`sitemap: missing ${url}`);
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(`Validated ${pages.length} localized pages and ${sitemapUrls.length} sitemap URLs.`);
