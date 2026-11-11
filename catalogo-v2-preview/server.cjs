'use strict';
const http = require('node:http');
const { readFile } = require('node:fs/promises');
const { join } = require('node:path');

const types = {
  html: 'text/html; charset=utf-8',
  css: 'text/css; charset=utf-8',
  js: 'text/javascript; charset=utf-8',
  svg: 'image/svg+xml',
};
const files = new Set([
  'index.html', 'preview.css', 'catalogo-core.js', 'fixtures.js', 'preview.js',
  ...['yerba','galletas','aceite','jugo','arroz','cafe','papas'].map(name => 'img/' + name + '.svg'),
]);

function createPreviewServer() {
  return http.createServer(async (req, res) => {
    const pathname = req.url.split('?')[0];
    const file = pathname === '/' ? 'index.html' : pathname.slice(1);
    const validHost = /^127\.0\.0\.1:\d+$/.test(req.headers.host || '');
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (req.method !== 'GET' || !validHost || !files.has(file)) {
      res.writeHead(404).end();
      return;
    }
    try {
      res.setHeader('Content-Type', types[file.split('.').at(-1)]);
      res.end(await readFile(join(__dirname, file)));
    } catch {
      res.writeHead(404).end();
    }
  });
}

if (require.main === module) {
  createPreviewServer().listen(4179, '127.0.0.1', () =>
    console.log('Vista previa ficticia: http://127.0.0.1:4179/'));
}
module.exports = { createPreviewServer };
