// Genera src/catalogo.500.json (ignorado por git) para probar el rendimiento con 500 productos.
//
//   node test/helpers/generar-500.js
//   VITRINA_CATALOGO=catalogo.500.json npm start      (PowerShell: $env:VITRINA_CATALOGO='catalogo.500.json'; npm start)
//
// Es determinista: siempre genera lo mismo.

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const CATEGORIAS = ['Golosinas', 'Lácteos', 'Bebidas', 'Almacén', 'Panadería', 'Limpieza', 'Fiambres', 'Verdulería'];
const NOMBRES = ['Alfajor', 'Galletitas', 'Queso', 'Gaseosa', 'Yerba mate', 'Pan', 'Jabón', 'Jamón', 'Manzana', 'Café', 'Leche', 'Fideos'];
const ADJETIVOS = ['triple', 'suave', 'clásico', 'de chocolate', 'light', 'familiar', 'con palo, paquete de 500 g', 'extra grande'];

export function generarCatalogo(cantidad = 500) {
  const productos = [];
  for (let i = 0; i < cantidad; i++) {
    const precio = 50000 + ((i * 7919) % 900000);
    const porKilo = i % 9 === 0;
    const producto = {
      id: `p-${String(i + 1).padStart(4, '0')}`,
      nombre: `${NOMBRES[i % NOMBRES.length]} ${ADJETIVOS[(i * 3) % ADJETIVOS.length]} ${i + 1}`,
      descripcion: i % 4 === 0 ? undefined : `Descripción de prueba del producto número ${i + 1}`,
      categoria: CATEGORIAS[i % CATEGORIAS.length],
      precio_centavos: precio - (precio % 50),
      unidad: porKilo ? 'kg' : 'unidad',
      destacado: i % 25 === 0,
      visible: i % 40 !== 0,
    };
    if (i % 6 === 0) producto.precio_anterior_centavos = producto.precio_centavos + 20000;
    productos.push(producto);
  }
  return {
    formato: 1,
    comercio: {
      id: 'kiosco-500',
      nombre: 'Kiosco de Prueba (500 productos)',
      whatsapp: '5490000000000',
      actualizado: '2026-11-12',
      tema: 'azul',
    },
    productos,
  };
}

const esPrincipal = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (esPrincipal) {
  const destino = new URL('../../src/catalogo.500.json', import.meta.url);
  writeFileSync(destino, JSON.stringify(generarCatalogo(500), null, 1) + '\n');
  console.log(`Generado ${fileURLToPath(destino)}`);
}
