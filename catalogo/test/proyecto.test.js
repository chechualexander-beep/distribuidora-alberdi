import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

test('package.json: módulos ES y sin dependencias', () => {
  assert.equal(pkg.type, 'module');
  assert.equal(pkg.dependencies, undefined);
  assert.equal(pkg.devDependencies, undefined);
  assert.deepEqual(Object.keys(pkg.scripts).sort(), ['armar', 'start', 'start:red', 'test']);
});

function archivosDeTexto(carpeta, extensiones) {
  const salida = [];
  for (const entrada of readdirSync(carpeta, { withFileTypes: true })) {
    const ruta = join(carpeta, entrada.name);
    if (entrada.isDirectory()) salida.push(...archivosDeTexto(ruta, extensiones));
    else if (extensiones.some((e) => entrada.name.endsWith(e))) salida.push(ruta);
  }
  return salida;
}

test('no queda ninguna referencia a "Abierto hoy" (ni al campo viejo "horario") en src, docs ni README', () => {
  const raiz = fileURLToPath(new URL('../', import.meta.url));
  const archivos = [
    ...archivosDeTexto(join(raiz, 'src'), ['.js', '.css', '.html', '.json', '.svg']).filter((f) => !f.endsWith('catalogo.500.json')),
    ...archivosDeTexto(join(raiz, 'docs'), ['.md']),
    join(raiz, 'README.md'),
  ];
  assert.ok(archivos.length > 8);
  for (const archivo of archivos) {
    const texto = readFileSync(archivo, 'utf8');
    assert.doesNotMatch(texto, /Abierto hoy/i, archivo);
    // El campo viejo "horario" (singular) no se usa en ningún lado de src. Se exceptúan core.js (un
    // comentario que explica que se ignora) y los docs (que documentan que ya no se usa).
    if (archivo.includes(`${join('src', '')}`) && !archivo.endsWith('core.js')) {
      assert.doesNotMatch(texto, /\bhorario\b/i, archivo);
    }
  }
});
