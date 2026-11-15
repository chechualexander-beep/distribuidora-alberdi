// Conexión con Supabase (Distribuidora Alberdi). Solo clave publicable: las tablas no se
// consultan desde esta página, únicamente las funciones públicas del catálogo.
import { CONFIG } from './config.js';
import { clasificarError } from './alberdi-core.js';

export const esDemo = CONFIG.entorno === 'demo';
export const baseFotos = esDemo ? '' : `${CONFIG.supabaseUrl}/storage/v1/object/public/productos-fotos/`;

export class ErrorAlberdi extends Error {
  constructor({ tipo, mensaje }) {
    super(mensaje);
    this.tipo = tipo;
    this.mensaje = mensaje;
  }
}

async function rpc(nombre, cuerpo) {
  let respuesta;
  try {
    respuesta = await fetch(`${CONFIG.supabaseUrl}/rest/v1/rpc/${nombre}`, {
      method: 'POST',
      headers: { apikey: CONFIG.clavePublica, 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    throw new ErrorAlberdi(clasificarError({ red: true }));
  }
  let datos = null;
  try {
    datos = await respuesta.json();
  } catch {
    if (respuesta.ok) throw new ErrorAlberdi(clasificarError({ red: true }));
  }
  if (!respuesta.ok) throw new ErrorAlberdi(clasificarError({ estado: respuesta.status, cuerpo: datos }));
  return datos;
}

export function obtenerCatalogo(token) {
  return rpc('obtener_catalogo_cliente', { p_token: token });
}

/** pendiente = { p_solicitud_id, p_items, p_observacion }. Reintentar con el mismo UUID no duplica. */
export async function confirmarPedido(token, pendiente) {
  if (esDemo) {
    await new Promise((r) => setTimeout(r, 300));
    const total = pendiente.p_items.reduce((s, i) => s + Number(i.precio_visto) * i.cantidad, 0);
    return { pedido_id: `DEMO-${pendiente.p_solicitud_id.slice(0, 8)}`, total };
  }
  return rpc('crear_pedido_catalogo', { p_token: token, ...pendiente });
}
