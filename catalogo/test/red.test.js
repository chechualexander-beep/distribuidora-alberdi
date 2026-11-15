import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const { direccionesLocales } = require('../server.cjs');
const SERVIDOR = new URL('../server.cjs', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

const interfazFalsa = {
  Loopback: [{ family: 'IPv4', address: '127.0.0.1', internal: true }],
  'Wi-Fi': [
    { family: 'IPv6', address: 'fe80::1', internal: false },
    { family: 'IPv4', address: '192.168.1.20', internal: false },
  ],
  Virtual: [{ family: 'IPv4', address: '169.254.10.5', internal: false }],
  VPN: [{ family: 'IPv4', address: '8.8.4.4', internal: false }],
  Docker: [{ family: 4, address: '172.20.0.1', internal: false }],
  Repetida: [{ family: 'IPv4', address: '192.168.1.20', internal: false }],
};

test('direccionesLocales: solo IPv4 de red, sin loopback ni link-local, privadas primero, sin repetir', () => {
  assert.deepEqual(direccionesLocales(interfazFalsa), [
    { nombre: 'Wi-Fi', ip: '192.168.1.20' },
    { nombre: 'Docker', ip: '172.20.0.1' }, // privada pero virtual
    { nombre: 'VPN', ip: '8.8.4.4' },
  ]);
  // Una privada de adaptador virtual queda después de la del Wi-Fi aunque aparezca primero.
  assert.equal(
    direccionesLocales({
      'vEthernet (WSL)': [{ family: 'IPv4', address: '172.24.112.1', internal: false }],
      'Wi-Fi': [{ family: 'IPv4', address: '192.168.0.106', internal: false }],
    })[0].ip,
    '192.168.0.106',
  );
  assert.deepEqual(direccionesLocales({}), []);
});

function levantar(args, puerto) {
  return new Promise((resolve, reject) => {
    const hijo = spawn(process.execPath, [SERVIDOR, ...args], {
      env: { ...process.env, PORT: String(puerto) },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let salida = '';
    const alTerminar = (d) => {
      salida += d;
      if (/Vitrina en/.test(salida) && /\n/.test(salida) && (args.includes('--red') ? /Ctrl\+C/.test(salida) : true)) resolve({ hijo, salida: () => salida });
    };
    hijo.stdout.on('data', alTerminar);
    hijo.stderr.on('data', (d) => (salida += d));
    hijo.on('error', reject);
    setTimeout(() => reject(new Error(`El servidor no arrancó:\n${salida}`)), 8000);
  });
}

const apagar = (hijo) => new Promise((r) => { hijo.once('exit', r); hijo.kill(); });
const CSP = /Content-Security-Policy:\s*(.+)/.exec(readFileSync(new URL('../src/_headers', import.meta.url), 'utf8'))[1].trim();

test('start:red escucha en la red local, imprime la URL con la IP y mantiene la CSP', async () => {
  const { hijo, salida } = await levantar(['--red'], 4391);
  try {
    const ips = direccionesLocales();
    for (const { ip } of ips) assert.match(salida(), new RegExp(`http://${ip.replaceAll('.', '\\.')}:4391`));
    assert.match(salida(), /http:\/\/localhost:4391/);
    assert.match(salida(), /Ctrl\+C/);

    for (const host of ['127.0.0.1', ...ips.slice(0, 1).map((d) => d.ip)]) {
      const r = await fetch(`http://${host}:4391/`);
      assert.equal(r.status, 200, host);
      assert.equal(r.headers.get('content-security-policy'), CSP);
      assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
    }
  } finally {
    await apagar(hijo);
  }
});

test('npm start normal escucha solo en localhost (no responde por la IP de red)', async () => {
  const { hijo, salida } = await levantar([], 4392);
  try {
    assert.match(salida(), /http:\/\/localhost:4392/);
    assert.equal((await fetch('http://127.0.0.1:4392/')).status, 200);
    const [primera] = direccionesLocales();
    if (primera) {
      await assert.rejects(fetch(`http://${primera.ip}:4392/`, { signal: AbortSignal.timeout(2000) }));
    }
  } finally {
    await apagar(hijo);
  }
});
