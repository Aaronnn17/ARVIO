// Test-only server. Synthetic media lives outside the deployed public directory.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { build } = require(process.env.ESBUILD_PATH || '../../netlify-auth-site/node_modules/esbuild');
const root = path.resolve(__dirname, '..');
const media = path.resolve(root, '../.playback-fixtures');
const port = Number(process.env.PORT || 3099);
(async () => {
  const bundle = await build({ entryPoints: { app: path.join(__dirname, 'fixtures/playback-ui.ts'), 'remux.worker': path.join(root, 'lib/remux.worker.ts'),
    'dolbyVisionProbe.worker': path.join(root, 'lib/dolbyVisionProbe.worker.ts') },
    bundle: true, splitting: true, format: 'esm', outdir: '/fixture', write: false, define: {
      'process.env': JSON.stringify({ NODE_ENV: 'test', NEXT_PUBLIC_ARVIO_RESOLVER_URL: process.env.NEXT_PUBLIC_ARVIO_RESOLVER_URL || '' })
    } });
  const files = new Map(bundle.outputFiles.map(file => [path.basename(file.path), file.contents]));
  http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');
    const url = new URL(req.url, 'http://localhost');
    const name = path.basename(url.pathname).replace(/\.worker\.ts$/, '.worker.js');
    if (files.has(name)) { res.setHeader('Content-Type', 'text/javascript'); res.end(files.get(name)); return; }
    if (url.pathname.startsWith('/media/')) {
      const file = path.resolve(media, decodeURIComponent(url.pathname.slice(7)));
      if (!file.startsWith(media + path.sep) || !fs.existsSync(file)) { res.writeHead(404).end(); return; }
      const size = fs.statSync(file).size;
      const range = req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
      const start = range ? Number(range[1]) : 0;
      const end = range?.[2] ? Math.min(size - 1, Number(range[2])) : size - 1;
      if (start >= size || end < start) { res.writeHead(416, { 'Content-Range': `bytes */${size}` }).end(); return; }
      const type = file.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : file.endsWith('.ts') ? 'video/mp2t' : file.endsWith('.mp4') ? 'video/mp4' : 'video/x-matroska';
      res.writeHead(range ? 206 : 200, { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1,
        ...(range ? { 'Content-Range': `bytes ${start}-${end}/${size}` } : {}) });
      fs.createReadStream(file, { start, end }).pipe(res); return;
    }
    res.setHeader('Content-Type', 'text/html');
    res.end('<!doctype html><html><head><title>ARVIO playback verification</title><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><script type="module" src="/app.js"></script></body></html>');
  }).listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}`));
})().catch(error => { console.error(error); process.exit(1); });
