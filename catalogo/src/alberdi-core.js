// Adaptador Distribuidora Alberdi: funciones puras (sin red ni DOM), probadas en test/alberdi.test.js.
// Convierten la respuesta de obtener_catalogo_cliente / obtener_catalogo_general al formato de
// Vitrina y arman el pedido: el del cliente va a crear_pedido_catalogo (precio_visto tal cual lo
// mandó el servidor); el del catálogo general sale por WhatsApp al preventista.

import { formatearPrecio, esWhatsappValido } from './core.js';

export const REGEX_TOKEN = /^[a-f0-9]{64}$/;
const REGEX_FOTO = /^[a-f0-9-]{36}\/[0-9]+\.jpg$/;

/**
 * Enlace de Alberdi en el hash: "#token=<64 hex>" (catálogo del cliente) o "#general=<64 hex>"
 * (catálogo general del preventista). Devuelve { tipo: 'cliente' | 'general', token } o null.
 */
export function enlaceDesdeHash(hash) {
  const texto = typeof hash === 'string' ? hash.replace(/^#/, '') : '';
  if (!texto.includes('token=') && !texto.includes('general=')) return null;
  const params = new URLSearchParams(texto);
  for (const [clave, tipo] of [['token', 'cliente'], ['general', 'general']]) {
    const token = params.get(clave) ?? '';
    if (REGEX_TOKEN.test(token)) return { tipo, token };
  }
  return null;
}

/** Token del catálogo del cliente ("#token=…"), o null. */
export function tokenDesdeHash(hash) {
  const enlace = enlaceDesdeHash(hash);
  return enlace?.tipo === 'cliente' ? enlace.token : null;
}

/** Fecha AAAA-MM-DD en Argentina (UTC-3), para "Precios actualizados el…". */
export function hoyArgentina(ahora = new Date()) {
  const ar = new Date(ahora.getTime() - 3 * 60 * 60 * 1000);
  return ar.toISOString().slice(0, 10);
}

/** "15/11 a las 12:30" en hora argentina. */
export function formatearVencimiento(iso) {
  const fecha = new Date(iso);
  if (Number.isNaN(fecha.getTime())) return '';
  const ar = new Date(fecha.getTime() - 3 * 60 * 60 * 1000);
  const dos = (n) => String(n).padStart(2, '0');
  return `${dos(ar.getUTCDate())}/${dos(ar.getUTCMonth() + 1)} a las ${dos(ar.getUTCHours())}:${dos(ar.getUTCMinutes())}`;
}

function adaptarProductos(lista) {
  const precios = new Map();
  const codigos = new Map();
  const productos = [];
  for (const p of lista) {
    const precio = Number(p?.precio);
    const centavos = Math.round(precio * 100);
    if (typeof p?.id !== 'string' || !Number.isFinite(precio) || centavos < 1) continue;
    precios.set(p.id, p.precio);
    const codigo = String(p.codigo ?? '').trim();
    if (codigo) codigos.set(p.id, codigo);
    const producto = {
      id: p.id,
      nombre: String(p.nombre ?? '').trim() || 'Producto',
      categoria: String(p.categoria ?? '').trim() || 'Otros',
      unidad: 'unidad',
      precio_centavos: centavos,
    };
    const detalle = [p.descripcion, codigo ? `Código ${codigo}` : '']
      .map((t) => String(t ?? '').trim())
      .filter(Boolean)
      .join(' · ');
    if (detalle) producto.descripcion = Array.from(detalle).slice(0, 200).join('');
    if (typeof p.foto_path === 'string' && REGEX_FOTO.test(p.foto_path)) producto.miniatura = p.foto_path;
    productos.push(producto);
  }
  return { productos, precios, codigos };
}

function comercioAlberdi(id, hoy) {
  return { id, nombre: 'Distribuidora Alberdi', tema: 'alberdi', actualizado: hoy };
}

/**
 * Respuesta de obtener_catalogo_cliente -> { json (formato Vitrina), precios (id -> precio original),
 * cliente, venceAt }. Omite productos sin precio válido.
 */
export function adaptarCatalogo(respuesta, { token, hoy = hoyArgentina() }) {
  if (!respuesta || typeof respuesta !== 'object' || !Array.isArray(respuesta.productos)) {
    throw new Error('Respuesta de catálogo inválida');
  }
  const { productos, precios } = adaptarProductos(respuesta.productos);
  return {
    json: { formato: 1, comercio: comercioAlberdi(`alberdi-${token.slice(0, 16)}`, hoy), productos },
    precios,
    cliente: String(respuesta.nombre_comercio ?? '').trim(),
    venceAt: respuesta.vence_at ?? null,
  };
}

/**
 * Respuesta de obtener_catalogo_general -> { json (con el WhatsApp del preventista), precios, codigos,
 * vendedor, venceAt }. Sin WhatsApp válido no hay a quién mandar el pedido: se rechaza.
 */
export function adaptarCatalogoGeneral(respuesta, { token, hoy = hoyArgentina() }) {
  if (!respuesta || typeof respuesta !== 'object' || !Array.isArray(respuesta.productos)) {
    throw new Error('Respuesta de catálogo inválida');
  }
  const whatsapp = String(respuesta.whatsapp ?? '');
  if (!esWhatsappValido(whatsapp)) throw new Error('Catálogo sin WhatsApp válido');
  const { productos, precios, codigos } = adaptarProductos(respuesta.productos);
  return {
    json: {
      formato: 1,
      comercio: { ...comercioAlberdi(`alberdi-g-${token.slice(0, 16)}`, hoy), whatsapp },
      productos,
    },
    precios,
    codigos,
    vendedor: String(respuesta.vendedor ?? '').trim(),
    venceAt: respuesta.vence_at ?? null,
  };
}

export const MAX_MENSAJE_ALBERDI = 3500;

const unaLinea = (t) => String(t ?? '').replace(/\s+/g, ' ').trim();

/**
 * Mensaje de WhatsApp del catálogo general: productos con código (para cargarlo rápido en la app),
 * total, quién pide y la aclaración. { texto, excedeLimite }.
 */
export function mensajeGeneral({ lineas, codigos = new Map(), vendedor = '', nombre = '', aclaracion = '' }) {
  const saludo = unaLinea(vendedor) ? `Hola ${unaLinea(vendedor)}, quiero hacer un pedido:` : 'Hola, quiero hacer un pedido:';
  const filas = [saludo];
  let total = 0;
  for (const { producto, cantidad, subtotal } of lineas) {
    total += subtotal;
    const codigo = codigos.get(producto.id);
    filas.push(`• ${cantidad} × ${producto.nombre}${codigo ? ` (${codigo})` : ''} — ${formatearPrecio(subtotal)}`);
  }
  filas.push(`Total: ${formatearPrecio(total)}`);
  const quien = unaLinea(nombre);
  if (quien) filas.push(`Soy ${quien}.`);
  const nota = String(aclaracion ?? '').split('\n').map(unaLinea).filter(Boolean).join('\n');
  if (nota) filas.push(nota);
  filas.push('Catálogo de Distribuidora Alberdi');
  const texto = filas.join('\n');
  return { texto, excedeLimite: texto.length > MAX_MENSAJE_ALBERDI };
}

/** Líneas del carrito -> p_items de crear_pedido_catalogo. */
export function itemsDelPedido(lineas, precios) {
  return lineas
    .filter(({ producto, cantidad }) => cantidad > 0 && precios.has(producto.id))
    .map(({ producto, cantidad }) => ({
      producto_id: producto.id,
      cantidad,
      precio_visto: precios.get(producto.id),
    }));
}

/** Clasifica un error de la API: vencido (410), incierto (red/5xx) o definitivo. */
export function clasificarError({ estado, cuerpo, red = false }) {
  if (red) {
    return { tipo: 'incierto', mensaje: 'No pudimos confirmar la conexión. Volvé a intentar: tu pedido no se va a duplicar.' };
  }
  const mensaje = (cuerpo && typeof cuerpo.message === 'string' && cuerpo.message) || 'No se pudo completar la operación.';
  if (estado === 410) return { tipo: 'vencido', mensaje };
  if (estado >= 500 || estado === 408 || estado === 429) return { tipo: 'incierto', mensaje: 'No pudimos confirmar el pedido. Volvé a intentar: no se va a duplicar.' };
  return { tipo: 'definitivo', mensaje };
}
