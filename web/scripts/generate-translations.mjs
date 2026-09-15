import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const resources = path.resolve(root, '../app/src/main/res');
const decode = text => text.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').replace(/<[^>]*>/g, '')
  .replace(/&#(x[\da-f]+|\d+);/gi, (_, n) => String.fromCodePoint(n[0] === 'x' ? parseInt(n.slice(1), 16) : Number(n)))
  .replace(/&(lt|gt|amp|quot|apos);/g, (_, e) => ({lt:'<',gt:'>',amp:'&',quot:'"',apos:"'"}[e]))
  .replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\(["'@?\\])/g, '$1').replace(/^"([\s\S]*)"$/, '$1');
function read(file) {
  return Object.fromEntries([...fs.readFileSync(file, 'utf8').matchAll(/<string\s+([^>]*\bname="([^"]+)"[^>]*)>([\s\S]*?)<\/string>/g)]
    .filter(m => !/translatable="false"/.test(m[1])).map(m => [m[2], decode(m[3])]));
}
const english = read(path.join(resources, 'values/strings.xml'));
const output = path.join(root, 'public/i18n');
fs.mkdirSync(output, {recursive:true});
const manifest = {};
for (const dir of fs.readdirSync(resources).filter(d => /^values-[a-z]{2}(-r[A-Z]{2})?$/.test(d))) {
  const file = path.join(resources, dir, 'strings.xml');
  if (!fs.existsSync(file)) continue;
  const locale = dir.slice(7).replace('-r', '-').replace(/^iw$/, 'he').replace(/^in$/, 'id');
  const translated = read(file);
  const dictionary = {};
  // Keep the primary resource when Android has several context-specific IDs
  // with the same English wording. Web-specific overrides remain explicit.
  for (const [key, value] of Object.entries(translated)) if (english[key] && value && !(english[key] in dictionary)) dictionary[english[key]] = value;
  const extra = path.join(root, 'lib/i18n', `${locale}.json`);
  if (fs.existsSync(extra)) Object.assign(dictionary, JSON.parse(fs.readFileSync(extra, 'utf8')));
  const data = JSON.stringify(dictionary);
  fs.writeFileSync(path.join(output, `${locale}.json`), data + '\n');
  manifest[locale] = crypto.createHash('sha256').update(data).digest('hex').slice(0, 12);
}
fs.mkdirSync(path.join(root, 'lib/i18n'), {recursive:true});
fs.writeFileSync(path.join(root, 'lib/i18n/manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Exported ${Object.keys(manifest).length} Android interface languages.`);
