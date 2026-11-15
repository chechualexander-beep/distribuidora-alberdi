// Adaptador Distribuidora Alberdi: funciones puras (sin red ni DOM), probadas en test/alberdi.test.js.
// Convierten la respuesta de obtener_catalogo_cliente al formato de Vitrina y arman el pedido
// para crear_pedido_catalogo. Los precios viajan al servidor tal cual los mandó (precio_visto).

export const REGEX_TOKEN = /^[a-f0-9]{64}$/;
const REGEX_FOTO = /^[a-f0-9-]{36}\/[0-9]+\.jpg$/;

/** Lee el token de un hash "#token=<64 hex>" (formato de los enlaces que genera Alberdi). */
export function tokenDesdeHash(hash) {
  const texto = typeof hash === 'string' ? hash.replace(/^#/, '') : '';
  if (!texto.includes('token=')) return null;
  const token = new URLSearchParams(texto).get('token') ?? '';
  return REGEX_TOKEN.test(token) ? token : null;
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

/**
 * Respuesta de obtener_catalogo_cliente -> { json (formato Vitrina), precios (id -> precio original),
 * cliente, venceAt }. Omite productos sin precio válido.
 */
export function adaptarCatalogo(respuesta, { token, hoy = hoyArgentina() }) {
  if (!respuesta || typeof respuesta !== 'object' || !Array.isArray(respuesta.productos)) {
    throw new Error('Respuesta de catálogo inválida');
  }
  const precios = new Map();
  const productos = [];
  for (const p of respuesta.productos) {
    const precio = Number(p?.precio);
    const centavos = Math.round(precio * 100);
    if (typeof p?.id !== 'string' || !Number.isFinite(precio) || centavos < 1) continue;
    precios.set(p.id, p.precio);
    const producto = {
      id: p.id,
      nombre: String(p.nombre ?? '').trim() || 'Producto',
      categoria: String(p.categoria ?? '').trim() || 'Otros',
      unidad: 'unidad',
      precio_centavos: centavos,
    };
    const detalle = [p.descripcion, p.codigo ? `Código ${p.codigo}` : '']
      .map((t) => String(t ?? '').trim())
      .filter(Boolean)
      .join(' · ');
    if (detalle) producto.descripcion = Array.from(detalle).slice(0, 200).join('');
    if (typeof p.foto_path === 'string' && REGEX_FOTO.test(p.foto_path)) producto.miniatura = p.foto_path;
    productos.push(producto);
  }
  return {
    json: {
      formato: 1,
      comercio: {
        id: `alberdi-${token.slice(0, 16)}`,
        nombre: 'Distribuidora Alberdi',
        tema: 'alberdi',
        actualizado: hoy,
      },
      productos,
    },
    precios,
    cliente: String(respuesta.nombre_comercio ?? '').trim(),
    venceAt: respuesta.vence_at ?? null,
  };
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
