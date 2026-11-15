'use strict';
// Servidor estático local, sin dependencias. Sirve la carpeta src/ en el puerto 4180.
// Los headers (CSP, caché, etc.) salen de src/_headers, la misma fuente que usa
// Cloudflare Pages, así que lo que se prueba acá es lo que se publica.
//
//   npm start                       → http://localhost:4180 (solo esta compu)
//   npm run start:red               → 0.0.0.0:4180 e imprime la URL con la IP local (para el celular)
//   PORT=5000 npm start             → otro puerto
//   VITRINA_CATALOGO=catalogo.500.json npm start
//                                   → /catalogo.json sirve ese archivo (pruebas de rendimiento)
//   VITRINA_URL_PUBLICA=https://kiosco.ejemplo.com npm start
//                                   → la vista previa del enlace del index.html incluye og:url y og:image
//
// Vista previa del enlace: el index.html trae el marcador <!--VITRINA_META-->. Este servidor lo
// reemplaza con las etiquetas de tool/meta.mjs usando src/catalogo.json (solo para verlo en
// desarrollo). En el sitio publicado lo reemplaza quien arma el sitio (Super POS).

const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const RAIZ_POR_DEFECTO = path.join(__dirname, 'src');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

// Archivos de configuración del hosting: nunca se sirven.
const ARCHIVOS_OCULTOS = new Set(['_headers', '_redirects']);

/** Interpreta un archivo _headers (formato Cloudflare Pages) en una lista de reglas. */
function leerReglasHeaders(texto) {
  const reglas = [];
  let actual = null;
  for (const linea of texto.split(/\r?\n/)) {
    if (linea.trim() === '' || linea.trim().startsWith('#')) continue;
    if (/^\s/.test(linea)) {
      const i = linea.indexOf(':');
      if (actual && i > 0) {
        actual.headers.push([linea.slice(0, i).trim(), linea.slice(i + 1).trim()]);
      }
    } else {
      actual = { patron: linea.trim(), headers: [] };
      reglas.push(actual);
    }
  }
  return reglas;
}

function patronARegex(patron) {
  const escapado = patron.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
  return new RegExp(`^${escapado}$`);
}

/** Headers que corresponden a una ruta: se juntan todas las reglas que coinciden. */
function headersPara(reglas, ruta) {
  const resultado = new Map();
  for (const regla of reglas) {
    if (!patronARegex(regla.patron).test(ruta)) continue;
    for (const [nombre, valor] of regla.headers) {
      const clave = nombre.toLowerCase();
      const previo = resultado.get(clave);
      resultado.set(clave, previo ? { nombre, valor: `${previo.valor}, ${valor}` } : { nombre, valor });
    }
  }
  return [...resultado.values()];
}

/**
 * Solo desarrollo: reemplaza el marcador <!--VITRINA_META--> de index.html por las etiquetas de
 * vista previa del enlace (tool/meta.mjs) usando el catalogo.json local. En el sitio publicado lo
 * hace quien arma el sitio (Super POS). Si el catálogo no se puede leer o es inválido, devuelve el
 * HTML tal cual.
 */
let modulosMeta = null;
async function completarMeta(html, { raiz, archivoCatalogo, urlPublica }) {
  const raizProyecto = __dirname;
  modulosMeta ??= Promise.all([
    import(pathToFileURL(path.join(raizProyecto, 'tool', 'meta.mjs')).href),
    import(pathToFileURL(path.join(raizProyecto, 'src', 'core.js')).href),
  ]);
  const [{ MARCADOR, armarMeta }, { validarCatalogo, productosVisibles }] = await modulosMeta;
  if (!html.includes(MARCADOR)) return html;
  try {
    const json = JSON.parse(fs.readFileSync(path.join(raiz, archivoCatalogo), 'utf8'));
    const resultado = validarCatalogo(json);
    if (!resultado.ok) return html;
    const { comercio } = resultado.catalogo;
    const conFoto = productosVisibles(resultado.catalogo).find((p) => p.miniatura);
    const bloque = armarMeta({ nombre: comercio.nombre, urlPublica, foto: conFoto?.miniatura, tema: comercio.tema });
    return html
      .replace(/[ \t]*<title>Catálogo<\/title>\r?\n?/, '') // el título genérico sobra: lo trae el bloque
      .replace(MARCADOR, () => bloque.split('\n').join('\n  '));
  } catch {
    return html;
  }
}

function crearServidor({ raiz = RAIZ_POR_DEFECTO, catalogo = null, urlPublica = null } = {}) {
  const raizAbsoluta = path.resolve(raiz);
  if (catalogo !== null && !/^[A-Za-z0-9._-]+\.json$/.test(catalogo)) {
    throw new Error('VITRINA_CATALOGO tiene que ser un nombre de archivo .json simple (sin carpetas)');
  }

  let reglas = [];
  try {
    reglas = leerReglasHeaders(fs.readFileSync(path.join(raizAbsoluta, '_headers'), 'utf8'));
  } catch {
    console.warn('Aviso: no se pudo leer _headers; se sirve sin CSP.');
  }

  function responder(res, estado, ruta, extra = {}, cuerpo = null) {
    const headers = { 'Cache-Control': 'no-cache', ...extra };
    for (const { nombre, valor } of headersPara(reglas, ruta)) headers[nombre] = valor;
    res.writeHead(estado, headers);
    res.end(cuerpo);
  }

  return http.createServer((req, res) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return responder(res, 405, '/', { Allow: 'GET, HEAD', 'Content-Type': 'text/plain; charset=utf-8' }, 'Método no permitido');
    }

    let rutaUrl;
    try {
      rutaUrl = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    } catch {
      return responder(res, 400, '/', { 'Content-Type': 'text/plain; charset=utf-8' }, 'Pedido inválido');
    }
    if (rutaUrl.includes('\0')) {
      return responder(res, 400, '/', { 'Content-Type': 'text/plain; charset=utf-8' }, 'Pedido inválido');
    }

    const noEncontrado = () =>
      responder(res, 404, rutaUrl, { 'Content-Type': 'text/plain; charset=utf-8' }, req.method === 'HEAD' ? null : 'No encontrado');

    if (rutaUrl.endsWith('/')) rutaUrl += 'index.html';
    let relativa = rutaUrl.replace(/^\/+/, '');
    if (catalogo !== null && relativa === 'catalogo.json') relativa = catalogo;

    const archivo = path.resolve(raizAbsoluta, relativa);
    const dentro = archivo === raizAbsoluta || archivo.startsWith(raizAbsoluta + path.sep);
    if (!dentro || ARCHIVOS_OCULTOS.has(path.basename(archivo))) return noEncontrado();

    fs.stat(archivo, (err, stat) => {
      if (err || !stat.isFile()) return noEncontrado();
      const tipo = MIME[path.extname(archivo).toLowerCase()] || 'application/octet-stream';
      const headers = { 'Content-Type': tipo, 'Content-Length': stat.size, 'Cache-Control': 'no-cache' };
      for (const { nombre, valor } of headersPara(reglas, rutaUrl)) headers[nombre] = valor;

      if (path.relative(raizAbsoluta, archivo) === 'index.html') {
        // La portada pasa por completarMeta (vista previa del enlace); el resto se sirve tal cual.
        return fs.readFile(archivo, 'utf8', async (errLectura, html) => {
          if (errLectura) return noEncontrado();
          let salida = html;
          try {
            salida = await completarMeta(html, { raiz: raizAbsoluta, archivoCatalogo: catalogo ?? 'catalogo.json', urlPublica });
          } catch (e) {
            console.warn(`No se pudo completar la vista previa del enlace: ${e.message}`);
          }
          const cuerpo = Buffer.from(salida, 'utf8');
          headers['Content-Length'] = cuerpo.length;
          res.writeHead(200, headers);
          res.end(req.method === 'HEAD' ? undefined : cuerpo);
        });
      }

      res.writeHead(200, headers);
      if (req.method === 'HEAD') return res.end();
      const flujo = fs.createReadStream(archivo);
      flujo.on('error', () => res.destroy());
      flujo.pipe(res);
    });
  });
}

/**
 * Direcciones IPv4 de esta compu en la red local, como [{ nombre, ip }] (sin loopback ni
 * link-local). Primero las privadas de adaptadores reales (Wi-Fi, Ethernet); al final las
 * de adaptadores virtuales (WSL, Hyper-V, VirtualBox, Docker...) y las no privadas.
 */
function direccionesLocales(interfaces = os.networkInterfaces()) {
  const esPrivada = (ip) => /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(ip);
  const esVirtual = (nombre) => /virtual|vethernet|wsl|hyper-v|vmware|vbox|docker|loopback|tailscale|zerotier/i.test(nombre);
  const encontradas = new Map();
  for (const [nombre, lista] of Object.entries(interfaces)) {
    for (const i of lista ?? []) {
      const familiaV4 = i.family === 'IPv4' || i.family === 4;
      if (familiaV4 && !i.internal && !i.address.startsWith('169.254.') && !encontradas.has(i.address)) {
        encontradas.set(i.address, { nombre, ip: i.address });
      }
    }
  }
  const puntaje = ({ nombre, ip }) => (esPrivada(ip) ? 2 : 0) + (esVirtual(nombre) ? 0 : 1);
  return [...encontradas.values()].sort((a, b) => puntaje(b) - puntaje(a));
}

module.exports = { crearServidor, leerReglasHeaders, headersPara, direccionesLocales, MIME };

if (require.main === module) {
  const enRed = process.argv.includes('--red');
  const puerto = Number(process.env.PORT) || 4180;
  const host = process.env.HOST || (enRed ? '0.0.0.0' : '127.0.0.1');
  const catalogo = process.env.VITRINA_CATALOGO || null;
  const urlPublica = process.env.VITRINA_URL_PUBLICA || null;
  const servidor = crearServidor({ catalogo, urlPublica });
  servidor.on('error', (e) => {
    console.error(
      e.code === 'EADDRINUSE'
        ? `El puerto ${puerto} ya está en uso. Probá con otro: PORT=4181 npm start`
        : `No se pudo iniciar el servidor: ${e.message}`,
    );
    process.exit(1);
  });
  servidor.listen(puerto, host, () => {
    const nota = catalogo ? `  (catálogo: ${catalogo})` : '';
    if (!enRed) {
      console.log(`Vitrina en http://localhost:${puerto}${nota}`);
      return;
    }
    const ips = direccionesLocales();
    console.log(`Vitrina en la red local${nota}`);
    console.log('Abrila desde el celular (conectado al mismo Wi-Fi):');
    if (ips.length === 0) console.log('  (no encontré una IP de red; revisá que estés conectado al Wi-Fi)');
    for (const { nombre, ip } of ips) console.log(`  http://${ip}:${puerto}   (${nombre})`);
    console.log(`En esta compu también: http://localhost:${puerto}`);
    console.log('Cualquiera en tu red puede verla mientras esté prendida. Para apagarla: Ctrl+C');
  });
}
