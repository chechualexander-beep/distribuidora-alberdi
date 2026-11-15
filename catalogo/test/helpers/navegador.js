// Ayuda para probar la pantalla real con Edge/Chrome headless por CDP, sin dependencias.
// Si no hay navegador instalado, buscarNavegador() devuelve null y los tests se saltean solos.
// Se puede forzar uno con la variable VITRINA_NAVEGADOR=<ruta al ejecutable>.

import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export function buscarNavegador() {
  const pf = process.env.ProgramFiles;
  const pf86 = process.env['ProgramFiles(x86)'];
  const candidatos = [
    process.env.VITRINA_NAVEGADOR,
    pf86 && `${pf86}\\Microsoft\\Edge\\Application\\msedge.exe`,
    pf && `${pf}\\Microsoft\\Edge\\Application\\msedge.exe`,
    pf && `${pf}\\Google\\Chrome\\Application\\chrome.exe`,
    pf86 && `${pf86}\\Google\\Chrome\\Application\\chrome.exe`,
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/microsoft-edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  ].filter(Boolean);
  return candidatos.find((ruta) => existsSync(ruta)) ?? null;
}

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

export async function abrirNavegador(ejecutable, puerto = 9400 + Math.floor(Math.random() * 400)) {
  const perfil = mkdtempSync(join(tmpdir(), 'vitrina-nav-'));
  const proceso = spawn(
    ejecutable,
    [
      // VITRINA_NAVEGADOR_ARGS permite usar un Chrome "headless shell" (p. ej. en Linux sin escritorio).
      ...(process.env.VITRINA_NAVEGADOR_ARGS ? process.env.VITRINA_NAVEGADOR_ARGS.split(' ') : ['--headless=new']),
      `--remote-debugging-port=${puerto}`,
      `--user-data-dir=${perfil}`,
      '--no-first-run',
      '--disable-gpu',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  let objetivo;
  for (let i = 0; i < 60 && !objetivo; i++) {
    try {
      objetivo = (await (await fetch(`http://127.0.0.1:${puerto}/json`)).json()).find((t) => t.type === 'page');
    } catch {
      /* todavía no arrancó */
    }
    if (!objetivo) await esperar(200);
  }
  if (!objetivo) {
    proceso.kill();
    throw new Error('No arrancó el navegador headless');
  }

  const ws = new WebSocket(objetivo.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve);
    ws.addEventListener('error', reject);
  });

  let ultimoId = 0;
  const pendientes = new Map();
  let consola = [];
  ws.addEventListener('message', (m) => {
    const d = JSON.parse(m.data);
    if (d.id && pendientes.has(d.id)) {
      pendientes.get(d.id)(d);
      pendientes.delete(d.id);
    } else if (d.method === 'Runtime.consoleAPICalled') {
      consola.push({ tipo: d.params.type, texto: d.params.args.map((a) => a.value ?? a.description ?? '').join(' ') });
    }
  });
  const cdp = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++ultimoId;
      pendientes.set(id, (d) => (d.error ? reject(new Error(`${method}: ${JSON.stringify(d.error)}`)) : resolve(d.result)));
      ws.send(JSON.stringify({ id, method, params }));
    });

  await cdp('Page.enable');
  await cdp('Runtime.enable');

  let guion = null;

  const pagina = {
    /** Evalúa una expresión en la página y devuelve su valor (serializable). */
    async evaluar(expresion) {
      const r = await cdp('Runtime.evaluate', { expression: expresion, awaitPromise: true, returnByValue: true });
      if (r.exceptionDetails) throw new Error(`Error en la página: ${r.exceptionDetails.text} ${r.exceptionDetails.exception?.description ?? ''}`);
      return r.result.value;
    },
    /** Mensajes de consola desde la última apertura. */
    mensajesDeConsola: () => consola.slice(),
    /**
     * Abre la URL. `diaDeLaSemana` fija Date.getDay() (domingo = 0) para que "hoy" sea determinista.
     * Espera a que aparezca la cabecera (o la pantalla de error).
     */
    async abrir(url, { ancho = 390, alto = 844, diaDeLaSemana = null, escalaLetra = null } = {}) {
      consola = [];
      if (guion) await cdp('Page.removeScriptToEvaluateOnNewDocument', { identifier: guion });
      guion = null;
      const fuente = [
        diaDeLaSemana === null ? '' : `Date.prototype.getDay = function () { return ${Number(diaDeLaSemana)}; };`,
        'try { localStorage.clear(); } catch {}',
        escalaLetra ? `document.addEventListener('DOMContentLoaded', () => { document.documentElement.style.fontSize = '${escalaLetra}'; });` : '',
      ].join('\n');
      guion = (await cdp('Page.addScriptToEvaluateOnNewDocument', { source: fuente })).identifier;
      await cdp('Emulation.setDeviceMetricsOverride', { width: ancho, height: alto, deviceScaleFactor: 1, mobile: true });
      // Pasar por about:blank asegura una carga completa aunque la URL solo cambie en el #hash.
      await cdp('Page.navigate', { url: 'about:blank' });
      await esperar(100);
      await cdp('Page.navigate', { url });
      for (let i = 0; i < 50; i++) {
        await esperar(100);
        try {
          if (await pagina.evaluar("!!document.querySelector('.cabecera, .error-pantalla')")) return;
        } catch {
          /* la página todavía está cargando */
        }
      }
      throw new Error(`La página no terminó de cargar: ${url}`);
    },
    async cerrar() {
      try {
        ws.close();
      } catch {
        /* ya cerrado */
      }
      proceso.kill();
      await new Promise((r) => (proceso.exitCode !== null ? r() : proceso.once('exit', r)));
      for (let i = 0; i < 5; i++) {
        try {
          rmSync(perfil, { recursive: true, force: true });
          break;
        } catch {
          await esperar(200);
        }
      }
    },
  };
  return pagina;
}
