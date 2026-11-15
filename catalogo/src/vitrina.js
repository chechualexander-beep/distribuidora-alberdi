// Vitrina — interfaz. La lógica vive en core.js (funciones puras).
// Seguridad: todo texto que viene del JSON entra con textContent o atributos seguros.
// No se usa innerHTML, ni estilos o scripts inline (CSP estricta).

import {
  validarCatalogo,
  describirErrores,
  productosVisibles,
  indexarProductos,
  resolverTema,
  formatearPrecio,
  formatearCantidad,
  formatearFecha,
  filtrarProductos,
  obtenerCategorias,
  productosNovedades,
  productosOfertas,
  esOferta,
  obtenerIniciales,
  indiceParejaIniciales,
  masCantidad,
  menosCantidad,
  establecerCantidad,
  cantidadEnCarrito,
  cantidadDeProductos,
  lineasDelPedido,
  calcularTotal,
  reconciliarCarrito,
  mensajesDeAvisos,
  claveCarrito,
  crearAlmacen,
  serializarCarrito,
  detalleLinea,
  filasHorarios,
  textoHoy,
  RUTA_INICIO,
  RUTA_PEDIDO,
  hashDeFoto,
  resolverRuta,
} from './core.js';
import {
  adaptarCatalogo,
  adaptarCatalogoGeneral,
  itemsDelPedido,
  enlaceDesdeHash,
  formatearVencimiento,
  mensajeGeneral,
  aplicarPresentacion,
} from './alberdi-core.js';
import { urlWhatsApp } from './core.js';
import { esDemo, baseFotos, obtenerCatalogo, obtenerCatalogoGeneral, obtenerPresentacion, confirmarPedido } from './alberdi.js';

/* ---------- Ayudas para construir el DOM sin innerHTML ---------- */

function h(etiqueta, props = {}, hijos = []) {
  const nodo = document.createElement(etiqueta);
  for (const [clave, valor] of Object.entries(props)) {
    if (valor === undefined || valor === null || valor === false) continue;
    if (clave === 'clase') nodo.className = valor;
    else if (clave === 'texto') nodo.textContent = valor;
    else if (clave === 'style' || clave === 'innerHTML' || clave.startsWith('on')) {
      throw new Error(`Atributo no permitido: ${clave}`);
    } else nodo.setAttribute(clave, valor === true ? '' : String(valor));
  }
  for (const hijo of hijos) if (hijo) nodo.append(hijo);
  return nodo;
}

function flechaAtras() {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', '24');
  svg.setAttribute('height', '24');
  svg.setAttribute('aria-hidden', 'true');
  const trazo = document.createElementNS(ns, 'path');
  trazo.setAttribute('d', 'M15 5l-7 7 7 7M8.5 12H21');
  trazo.setAttribute('fill', 'none');
  trazo.setAttribute('stroke', 'currentColor');
  trazo.setAttribute('stroke-width', '2.5');
  trazo.setAttribute('stroke-linecap', 'round');
  trazo.setAttribute('stroke-linejoin', 'round');
  svg.append(trazo);
  return svg;
}

/* ---------- Estado ---------- */

const estado = {
  catalogo: null,
  productos: [], // solo visibles
  porId: new Map(),
  carrito: [],
  almacen: null,
  categoria: null,
  texto: '',
  // Alberdi
  modo: 'cliente', // 'cliente' (pedido directo) o 'general' (pedido por WhatsApp al preventista)
  vendedor: '',
  codigos: new Map(),
  token: null,
  cliente: '',
  venceAt: null,
  precios: new Map(), // id -> precio original (precio_visto)
  pendiente: null, // pedido enviado sin respuesta confirmada: se reintenta con el mismo UUID
  enviando: false,
  exito: null,
};

const CLAVE_ENLACE = 'alberdi:enlace';
const clavePendiente = () => `alberdi-pendiente:${estado.token ?? 'demo'}`;

function leerSesion(clave) {
  try {
    return sessionStorage.getItem(clave);
  } catch {
    return null;
  }
}

function escribirSesion(clave, valor) {
  try {
    if (valor === null) sessionStorage.removeItem(clave);
    else sessionStorage.setItem(clave, valor);
  } catch {
    /* modo privado: se sigue sin guardar */
  }
}

const textoEnlace = ({ tipo, token }) => `${tipo === 'general' ? 'general' : 'token'}=${token}`;

/**
 * Enlace del hash (#token=… o #general=…). Se guarda en la pestaña y el hash vuelve a las rutas de
 * la vitrina, así el token no queda a la vista ni en el historial.
 */
function leerEnlace() {
  const delHash = enlaceDesdeHash(location.hash);
  if (delHash) {
    escribirSesion(CLAVE_ENLACE, textoEnlace(delHash));
    history.replaceState(null, '', `${location.pathname}${location.search}#/`);
    return delHash;
  }
  return enlaceDesdeHash(leerSesion(CLAVE_ENLACE) ?? '');
}

function guardarPendiente() {
  escribirSesion(clavePendiente(), estado.pendiente ? JSON.stringify(estado.pendiente) : null);
}

const refs = {};
const filas = new Map(); // id -> { li, valor, menos, mas }
const tarjetas = new Map(); // id -> [{ aviso }]

/* ---------- Arranque ---------- */

function mostrarError(app, mensaje = 'No pudimos cargar el catálogo. Probá de nuevo en un rato.', reintentar = true) {
  app.replaceChildren(
    h('main', { clase: 'error-pantalla' }, [
      h('h1', { texto: mensaje }),
      reintentar && h('button', { clase: 'btn-secundario', type: 'button', texto: 'Probar de nuevo', id: 'reintentar' }),
    ]),
  );
  document.getElementById('reintentar')?.addEventListener('click', () => location.reload());
}

async function iniciar() {
  const app = document.getElementById('app');
  let json;
  try {
    if (esDemo) {
      const respuesta = await fetch('catalogo.json', { cache: 'no-cache' });
      if (!respuesta.ok) throw new Error(`HTTP ${respuesta.status}`);
      json = await respuesta.json();
      estado.precios = new Map((json.productos ?? []).map((p) => [p.id, (p.precio_centavos ?? 0) / 100]));
      // Demo del catálogo general: abrir con #general=<64 hex> (cualquiera).
      if (enlaceDesdeHash(location.hash)?.tipo === 'general' || /^general=/.test(leerSesion(CLAVE_ENLACE) ?? '')) {
        leerEnlace();
        estado.modo = 'general';
        estado.vendedor = 'Preventista de prueba';
        json.comercio.whatsapp = '5493794000000';
      } else {
        estado.cliente = 'Cliente de prueba';
      }
    } else {
      const enlace = leerEnlace();
      if (!enlace) {
        return mostrarError(app, 'Abrí el enlace que te compartió Distribuidora Alberdi para ver el catálogo.', false);
      }
      estado.token = enlace.token;
      // La presentación es opcional: si no llega, se muestra el catálogo con el estilo de siempre.
      const presentacion = obtenerPresentacion().catch((error) => {
        console.warn('Sin presentación del catálogo:', error);
        return null;
      });
      if (enlace.tipo === 'general') {
        const adaptado = adaptarCatalogoGeneral(await obtenerCatalogoGeneral(enlace.token), { token: enlace.token });
        estado.modo = 'general';
        json = adaptado.json;
        estado.precios = adaptado.precios;
        estado.codigos = adaptado.codigos;
        estado.vendedor = adaptado.vendedor;
        estado.venceAt = adaptado.venceAt;
      } else {
        const adaptado = adaptarCatalogo(await obtenerCatalogo(enlace.token), { token: enlace.token });
        json = adaptado.json;
        estado.precios = adaptado.precios;
        estado.cliente = adaptado.cliente;
        estado.venceAt = adaptado.venceAt;
      }
      json = aplicarPresentacion(json, await presentacion);
    }
  } catch (error) {
    console.warn('No se pudo cargar el catálogo:', error);
    if (error?.tipo === 'vencido') return mostrarError(app, error.mensaje, false);
    return mostrarError(app);
  }
  try {
    estado.pendiente = estado.modo === 'cliente' ? JSON.parse(leerSesion(clavePendiente()) ?? 'null') : null;
  } catch {
    estado.pendiente = null;
  }

  const resultado = validarCatalogo(json, { whatsappOpcional: true });
  if (!resultado.ok) {
    console.warn(`catalogo.json inválido:\n${describirErrores(resultado.errores)}`);
    return mostrarError(app);
  }
  if (resultado.avisos.length > 0) {
    console.warn(`catalogo.json: se ignoraron partes opcionales inválidas:\n${describirErrores(resultado.avisos)}`);
  }

  estado.catalogo = resultado.catalogo;
  estado.productos = productosVisibles(resultado.catalogo);
  estado.porId = indexarProductos(estado.productos);

  let storage = null;
  try {
    storage = window.localStorage;
  } catch {
    storage = null;
  }
  estado.almacen = crearAlmacen(storage, claveCarrito(resultado.catalogo.comercio.id));

  const guardado = estado.almacen.leer();
  const { carrito, avisos } = reconciliarCarrito(guardado, resultado.catalogo.productos);
  estado.carrito = carrito;
  if (serializarCarrito(carrito) !== serializarCarrito(guardado)) estado.almacen.guardar(carrito);

  aplicarTema(resultado.catalogo.comercio);
  const inicio = construirInicio(mensajesDeAvisos(avisos));
  const pedido = construirPedido();
  const visor = construirVisor();
  app.replaceChildren(inicio, pedido, visor);
  aplicarFiltro();
  actualizarBarra();

  window.addEventListener('hashchange', () => {
    // Abrir otro enlace de catálogo en la misma pestaña: se carga ese cliente.
    const otro = enlaceDesdeHash(location.hash);
    if (otro) {
      escribirSesion(CLAVE_ENLACE, textoEnlace(otro));
      history.replaceState(null, '', `${location.pathname}${location.search}#/`);
      location.reload();
      return;
    }
    if (resolverRuta(location.hash, estado.porId).pantalla === 'pedido') estado.navegoDentro = true;
    aplicarRuta();
  });
  document.addEventListener('keydown', alTeclear);
  aplicarRuta();
}

/* ---------- Rutas (#/, #/pedido y #/foto/<id>) ---------- */

/** Muestra lo que corresponde al hash actual: una pantalla base (inicio/pedido) y, encima, el visor si hay foto. */
function aplicarRuta() {
  const { pantalla, foto, corregirA } = resolverRuta(location.hash, estado.porId);
  if (corregirA !== null) {
    // Dirección inválida (producto inexistente o sin foto): se reemplaza, no se agrega al historial.
    history.replaceState(null, '', corregirA);
    return aplicarRuta();
  }
  mostrarPantalla(pantalla);
  if (foto) abrirVisor(foto);
  else cerrarVisorEnPantalla();
}

let pantallaMostrada = null;

function mostrarPantalla(ruta) {
  if (ruta === pantallaMostrada) return;
  if (pantallaMostrada === 'inicio') estado.scrollInicio = window.scrollY;
  pantallaMostrada = ruta;
  // El desplegable de horarios siempre vuelve a estar cerrado al cambiar de pantalla.
  if (refs.horarios) refs.horarios.removeAttribute('open');

  refs.inicio.hidden = ruta !== 'inicio';
  refs.pedido.hidden = ruta !== 'pedido';
  if (ruta === 'pedido') {
    renderPedido();
    window.scrollTo(0, 0);
    document.getElementById('titulo-pedido').focus({ preventScroll: true });
  } else {
    ocultarDeshacer();
    window.scrollTo(0, estado.scrollInicio ?? 0);
    document.getElementById('titulo-inicio').focus({ preventScroll: true });
  }
}

/** Vuelve a la vitrina: con el historial si vinimos de ella (así "atrás" del celular es consistente). */
function volverAInicio() {
  if (estado.navegoDentro) {
    estado.navegoDentro = false;
    history.back();
  } else {
    location.hash = RUTA_INICIO;
  }
}

function aplicarTema(comercio) {
  document.documentElement.setAttribute('data-tema', resolverTema(comercio.tema));
  document.title = `${comercio.nombre} · Catálogo`;
  const acento = getComputedStyle(document.documentElement).getPropertyValue('--acento').trim();
  // Si quien armó el sitio no completó la vista previa (<!--VITRINA_META-->), el theme-color se crea acá.
  let meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) {
    meta = h('meta', { name: 'theme-color' });
    document.head.append(meta);
  }
  if (acento) meta.setAttribute('content', acento);
}

/* ---------- Visor de foto a pantalla completa ---------- */

function construirVisor() {
  refs.visorImg = h('img', { clase: 'visor-img', alt: '' });
  refs.visorImg.addEventListener('error', pedirCerrarVisor); // si la foto no carga, no dejamos un visor vacío
  refs.visorNombre = h('p', { clase: 'visor-nombre' });
  refs.visorPrecio = h('p', { clase: 'visor-precio' });
  refs.visorCerrar = h('button', { clase: 'visor-cerrar', type: 'button', texto: 'Cerrar' });
  refs.visorCerrar.addEventListener('click', pedirCerrarVisor);

  refs.visor = h('div', { clase: 'visor', role: 'dialog', 'aria-modal': 'true', hidden: true }, [
    h('div', { clase: 'visor-barra' }, [refs.visorCerrar]),
    h('figure', { clase: 'visor-figura' }, [
      refs.visorImg,
      h('figcaption', { clase: 'visor-leyenda' }, [refs.visorNombre, refs.visorPrecio]),
    ]),
  ]);
  // Tocar fuera de la foto (el fondo o la leyenda) cierra; tocar la foto no.
  refs.visor.addEventListener('click', (evento) => {
    if (evento.target === refs.visorImg || evento.target.closest('.visor-cerrar')) return;
    pedirCerrarVisor();
  });
  return refs.visor;
}

function visorAbierto() {
  return refs.visor && !refs.visor.hidden;
}

function abrirVisor(producto) {
  if (visorAbierto() && estado.visorId === producto.id) return;
  const yaAbierto = visorAbierto();
  estado.visorId = producto.id;
  refs.visor.setAttribute('aria-label', `Foto de ${producto.nombre}`);
  refs.visorImg.src = baseFotos + producto.miniatura; // la misma URL que la miniatura: no se pide otra foto
  refs.visorNombre.textContent = producto.nombre;
  refs.visorPrecio.replaceChildren(...crearPrecio(producto));
  refs.visor.hidden = false;
  document.documentElement.classList.add('con-visor'); // sin scroll de la página de fondo
  refs.inicio.setAttribute('inert', '');
  refs.pedido.setAttribute('inert', '');
  if (!yaAbierto) refs.visorCerrar.focus({ preventScroll: true });
}

/** Oculta el visor y devuelve el foco a la miniatura que lo abrió. No toca el historial. */
function cerrarVisorEnPantalla() {
  if (!visorAbierto()) return;
  const id = estado.visorId;
  refs.visor.hidden = true;
  document.documentElement.classList.remove('con-visor');
  refs.inicio.removeAttribute('inert');
  refs.pedido.removeAttribute('inert');
  estado.visorId = null;
  estado.visorPorToque = false;

  const visible = (boton) => boton && boton.isConnected && boton.offsetParent !== null;
  let destino = visible(estado.botonFoto) ? estado.botonFoto : null;
  if (!destino) {
    destino = [...refs.inicio.querySelectorAll('[data-foto-id]')].find((b) => b.dataset.fotoId === id && visible(b)) ?? null;
  }
  estado.botonFoto = null;
  if (destino && pantallaMostrada === 'inicio') destino.focus({ preventScroll: true });
}

/**
 * Cierra el visor desde la interfaz (botón, tocar fuera, Escape o foto rota). Si lo abrió un toque
 * hay una entrada de historial propia: se vuelve con "atrás". Si se entró directo a la dirección
 * no hay a dónde volver dentro de la vitrina: se reemplaza por el inicio.
 */
function pedirCerrarVisor() {
  if (!visorAbierto()) return;
  if (estado.visorPorToque) {
    estado.visorPorToque = false;
    history.back();
  } else {
    history.replaceState(null, '', RUTA_INICIO);
    aplicarRuta();
  }
}

function alTeclear(evento) {
  if (!visorAbierto()) return;
  if (evento.key === 'Escape') {
    evento.preventDefault();
    pedirCerrarVisor();
  } else if (evento.key === 'Tab') {
    // El visor es modal y solo tiene un control: el foco se queda en "Cerrar".
    evento.preventDefault();
    refs.visorCerrar.focus({ preventScroll: true });
  }
}

/* ---------- Miniaturas ---------- */

/** Miniatura con foto real: un botón que abre el visor. Sin foto (o si falla): cuadro de iniciales, sin botón. */
function crearMiniatura(producto, clase, ancho, alto) {
  const caja = h('div', { clase: `miniatura ${clase} ini-${indiceParejaIniciales(producto.id)}` });
  const ponerIniciales = () => {
    caja.replaceChildren(h('span', { clase: 'iniciales', 'aria-hidden': 'true', texto: obtenerIniciales(producto.nombre) }));
  };
  if (producto.miniatura) {
    // width/height reservan el espacio (la caja ya tiene tamaño fijo en CSS): la página no salta al cargar.
    const img = h('img', { src: baseFotos + producto.miniatura, alt: '', width: ancho, height: alto, loading: 'lazy', decoding: 'async' });
    img.addEventListener('error', ponerIniciales, { once: true });
    const boton = h('button', {
      clase: 'miniatura-boton',
      type: 'button',
      'aria-label': `Ver foto de ${producto.nombre}`,
      'data-foto-id': producto.id,
    }, [img]);
    boton.addEventListener('click', () => {
      estado.botonFoto = boton;
      estado.visorPorToque = true;
      location.hash = hashDeFoto(producto.id); // entrada de historial propia: "atrás" cierra el visor
    });
    caja.append(boton);
  } else {
    ponerIniciales();
  }
  return caja;
}

function crearPrecio(producto, clasePrecio = 'precio') {
  const partes = [h('span', { clase: clasePrecio, texto: formatearPrecio(producto.precio_centavos) })];
  if (producto.unidad === 'kg') partes.push(h('span', { clase: 'precio-unidad', texto: ' / kg' }));
  if (esOferta(producto)) {
    partes.push(h('span', { clase: 'precio-antes', texto: `antes ${formatearPrecio(producto.precio_anterior_centavos)}` }));
  }
  return partes;
}

/* ---------- Pantalla de inicio ---------- */

/**
 * Desplegable "Horarios de atención" (<details> nativo, cerrado por defecto). Solo existe si el
 * comercio tiene `horarios`. "Hoy" sale del día de la semana del dispositivo (Date.getDay()).
 */
function construirHorarios(comercio) {
  if (!comercio.horarios) return null;
  const indiceHoy = new Date().getDay();
  // Espacios duros dentro de cada tramo ("8:00 a 12:00"): si hay que partir la línea, que sea en el "y".
  const sinCortes = (texto) => texto.replace(/(\d) a (\d)/g, '$1 a $2');
  const textoDeHoy = textoHoy(comercio.horarios, indiceHoy);

  const resumen = h('summary', { clase: 'horarios-resumen' }, [
    h('span', { clase: 'horarios-titulo', texto: 'Horarios de atención' }),
    textoDeHoy ? h('span', { clase: 'horarios-hoy', texto: sinCortes(textoDeHoy) }) : null,
  ]);

  const filas = filasHorarios(comercio.horarios, indiceHoy).map((fila) =>
    h('div', { clase: fila.esHoy ? 'horarios-fila es-hoy' : 'horarios-fila' }, [
      h('dt', { clase: 'horarios-dia' }, [
        document.createTextNode(`${fila.dia} `),
        fila.esHoy ? h('span', { clase: 'pastilla-hoy', texto: 'Hoy' }) : null,
      ]),
      h('dd', { clase: fila.cerrado ? 'horarios-tramos horarios-cerrado' : 'horarios-tramos', texto: sinCortes(fila.texto) }),
    ]),
  );

  const panel = h('div', { clase: 'horarios-panel' }, [
    h('dl', { clase: 'horarios-lista' }, filas),
    comercio.horarios_nota ? h('p', { clase: 'horarios-nota', texto: comercio.horarios_nota }) : null,
  ]);

  refs.horarios = h('details', { clase: 'horarios' }, [resumen, panel]);
  return refs.horarios;
}

function construirInicio(mensajes) {
  const { comercio } = estado.catalogo;
  refs.horarios = construirHorarios(comercio);

  const vence = estado.venceAt ? formatearVencimiento(estado.venceAt) : '';
  const general = estado.modo === 'general';
  const cabecera = h('header', { clase: 'cabecera' }, [
    h('div', { clase: 'interior' }, [
      h('img', { clase: 'logo', src: 'logo.png', alt: '', width: '240', height: '105' }),
      h('h1', { clase: 'sr-only', texto: comercio.nombre, tabindex: '-1', id: 'titulo-inicio' }),
      estado.cliente && h('p', { clase: 'saludo', texto: `Hola, ${estado.cliente}` }),
      general && estado.vendedor && h('p', { clase: 'saludo', texto: `Te atiende ${estado.vendedor}` }),
      h('p', {
        clase: 'pastilla',
        texto: !vence
          ? `Precios actualizados el ${formatearFecha(comercio.actualizado)}`
          : general
            ? `Precios válidos hasta el ${vence}`
            : `Podés hacer tu pedido hasta el ${vence}`,
      }),
      refs.horarios,
    ]),
  ]);

  // Línea de confianza, debajo del encabezado (el nombre entra con textContent).
  const confianza = h('p', {
    clase: 'confianza',
    texto: general
      ? `Este es el catálogo de ${comercio.nombre}. Elegí tus productos y mandá el pedido por WhatsApp a tu preventista: no hace falta registrarte ni pagar nada ahora.`
      : `Este es el catálogo de ${comercio.nombre}. Tu pedido llega directo a la distribuidora: no hace falta registrarte ni pagar nada ahora.`,
  });

  // Cartel de reconciliación del carrito (precios cambiados / productos quitados).
  const aviso = h('div', { clase: 'aviso', role: 'status', hidden: mensajes.length === 0 }, [
    h('p', { texto: mensajes.join('. ') }),
    h('button', { clase: 'btn-secundario', type: 'button', texto: 'Entendido' }),
  ]);
  aviso.querySelector('button').addEventListener('click', () => {
    aviso.hidden = true;
  });

  const entrada = h('input', {
    id: 'buscar',
    type: 'search',
    placeholder: 'Buscá un producto',
    autocomplete: 'off',
    autocapitalize: 'off',
    spellcheck: 'false',
    enterkeyhint: 'search',
  });
  entrada.addEventListener('input', () => {
    estado.texto = entrada.value;
    aplicarFiltro();
  });
  refs.buscador = entrada;
  const buscador = h('div', { clase: 'buscador' }, [
    h('label', { clase: 'sr-only', for: 'buscar', texto: 'Buscar producto' }),
    entrada,
  ]);

  // Categorías: "Todos" + orden de aparición.
  refs.chips = [];
  const grupoCategorias = h('div', { clase: 'categorias', role: 'group', 'aria-label': 'Categorías' });
  const crearChip = (categoria, etiqueta) => {
    const chip = h('button', { clase: 'chip', type: 'button', 'aria-pressed': 'false', texto: etiqueta });
    chip.addEventListener('click', () => {
      estado.categoria = categoria;
      aplicarFiltro();
    });
    refs.chips.push({ chip, categoria });
    grupoCategorias.append(chip);
  };
  crearChip(null, 'Todos');
  for (const categoria of obtenerCategorias(estado.productos)) crearChip(categoria, categoria);

  // Carriles.
  refs.carriles = h('div', { clase: 'carriles' });
  const novedades = productosNovedades(estado.productos);
  const ofertas = productosOfertas(estado.productos);
  if (novedades.length > 0) refs.carriles.append(crearCarril('Novedades', 'Nuevo', novedades));
  if (ofertas.length > 0) refs.carriles.append(crearCarril('Ofertas', 'Oferta', ofertas));

  // Lista completa.
  const lista = h('ul', { clase: 'filas' });
  const fragmento = document.createDocumentFragment();
  for (const producto of estado.productos) fragmento.append(crearFila(producto));
  lista.append(fragmento);

  refs.contador = h('p', { clase: 'contador', 'aria-live': 'polite' });
  const seccionLista = h('section', { clase: 'lista', 'aria-labelledby': 'titulo-lista' }, [
    h('div', { clase: 'lista-cabecera' }, [h('h2', { id: 'titulo-lista', texto: 'Todo lo que vendemos' }), refs.contador]),
    lista,
  ]);
  refs.lista = lista;

  const verTodo = h('button', { clase: 'btn-secundario', type: 'button', texto: 'Ver todo' });
  verTodo.addEventListener('click', () => {
    estado.texto = '';
    estado.categoria = null;
    entrada.value = '';
    aplicarFiltro();
    entrada.focus();
  });
  refs.sinResultados = h('div', { clase: 'sin-resultados', hidden: true }, [
    h('p', { texto: 'No encontramos ese producto', role: 'status' }),
    verTodo,
  ]);

  // Barra inferior fija.
  refs.barraEtiqueta = h('span');
  refs.barraTotal = h('span', { clase: 'total', 'aria-live': 'polite' });
  refs.barra = h('div', { clase: 'barra', hidden: true }, [
    h('div', { clase: 'interior' }, [
      h('a', { clase: 'btn-barra', href: RUTA_PEDIDO }, [refs.barraEtiqueta, refs.barraTotal]),
    ]),
  ]);

  refs.inicio = h('div', { clase: 'pantalla', id: 'pantalla-inicio' }, [
    cabecera,
    h('main', { clase: 'contenido' }, [
      h('div', { clase: 'interior' }, [confianza, aviso, buscador, grupoCategorias, refs.carriles, seccionLista, refs.sinResultados]),
    ]),
    refs.barra,
  ]);
  return refs.inicio;
}

function crearCarril(titulo, textoInsignia, productos) {
  const idTitulo = `titulo-${titulo.toLowerCase()}`;
  const lista = h('ul', { clase: 'carril-lista' });
  for (const producto of productos) lista.append(crearTarjeta(producto, textoInsignia));
  return h('section', { clase: 'carril', 'aria-labelledby': idTitulo }, [
    h('h2', { id: idTitulo, texto: titulo }),
    lista,
  ]);
}

function crearTarjeta(producto, textoInsignia) {
  const miniatura = crearMiniatura(producto, 'tarjeta-foto', 158, 84);
  miniatura.append(h('span', { clase: 'insignia', texto: textoInsignia }));

  const aviso = h('p', { clase: 'tarjeta-pedido', hidden: true });
  const boton = h('button', { clase: 'btn-agregar', type: 'button', texto: 'Agregar', 'aria-label': `Agregar ${producto.nombre} al pedido` });
  boton.addEventListener('click', () => cambiarCantidad(producto.id, +1));

  if (!tarjetas.has(producto.id)) tarjetas.set(producto.id, []);
  tarjetas.get(producto.id).push({ aviso });

  return h('li', { clase: 'tarjeta' }, [
    miniatura,
    h('div', { clase: 'tarjeta-cuerpo' }, [
      h('div', { clase: 'tarjeta-info' }, [
        h('h3', { clase: 'tarjeta-nombre', texto: producto.nombre }),
        h('p', { clase: 'tarjeta-precio' }, crearPrecio(producto)),
        aviso,
      ]),
      boton,
    ]),
  ]);
}

function crearFila(producto) {
  const esKg = producto.unidad === 'kg';
  const porPaso = esKg ? '¼ kg' : 'uno';
  const menos = h('button', {
    clase: 'btn-menos',
    type: 'button',
    texto: '−',
    'aria-label': `Sacar ${porPaso} de ${producto.nombre}`,
  });
  const mas = h('button', {
    clase: 'btn-mas',
    type: 'button',
    texto: '+',
    'aria-label': `Agregar ${porPaso} de ${producto.nombre}`,
  });
  const valor = h('output', { clase: 'cantidad-valor', texto: '0' });
  menos.addEventListener('click', () => cambiarCantidad(producto.id, -1));
  mas.addEventListener('click', () => cambiarCantidad(producto.id, +1));

  const li = h('li', { clase: 'fila-caja', 'data-id': producto.id }, [
    h('div', { clase: 'fila' }, [
      crearMiniatura(producto, 'fila-foto', 72, 72),
      h('div', { clase: 'fila-info' }, [
        h('h3', { clase: 'fila-nombre', texto: producto.nombre }),
        producto.descripcion ? h('p', { clase: 'fila-desc', texto: producto.descripcion }) : null,
        h('p', { clase: 'fila-precio' }, crearPrecio(producto)),
      ]),
      h('div', { clase: 'cantidad', role: 'group', 'aria-label': `Cantidad de ${producto.nombre}` }, [menos, valor, mas]),
    ]),
  ]);
  filas.set(producto.id, { li, valor, menos, mas });
  return li;
}

/* ---------- Actualizaciones de la interfaz ---------- */

function textoCantidad(producto, cantidad) {
  return cantidad === 0 ? '0' : formatearCantidad(producto.unidad, cantidad);
}

/** Actualiza solo los controles de un producto (no re-renderiza la lista, así el foco no se pierde). */
function actualizarProducto(id) {
  const producto = estado.porId.get(id);
  const cantidad = cantidadEnCarrito(estado.carrito, id);
  const fila = filas.get(id);
  if (fila) {
    fila.valor.textContent = textoCantidad(producto, cantidad);
    fila.menos.setAttribute('aria-disabled', String(cantidad === 0));
    fila.mas.setAttribute('aria-disabled', String(masCantidad(producto.unidad, cantidad) === cantidad));
  }
  for (const { aviso } of tarjetas.get(id) ?? []) {
    aviso.hidden = cantidad === 0;
    aviso.textContent = cantidad === 0 ? '' : `En tu pedido: ${textoCantidad(producto, cantidad)}`;
  }
}

function actualizarBarra() {
  const lineas = lineasDelPedido(estado.carrito, estado.porId);
  refs.barra.hidden = estado.carrito.length === 0;
  refs.barraEtiqueta.textContent = `Ver mi pedido · ${cantidadDeProductos(estado.carrito)}`;
  refs.barraTotal.textContent = formatearPrecio(calcularTotal(lineas));
}

/** Con un pedido enviado sin confirmar, el carrito no se toca hasta reintentar. */
function bloqueadoPorPendiente() {
  if (!estado.pendiente && !estado.enviando) return false;
  location.hash = RUTA_PEDIDO;
  return true;
}

function cambiarCantidad(id, direccion) {
  const producto = estado.porId.get(id);
  if (!producto || bloqueadoPorPendiente()) return;
  const actual = cantidadEnCarrito(estado.carrito, id);
  const nueva = direccion > 0 ? masCantidad(producto.unidad, actual) : menosCantidad(producto.unidad, actual);
  if (nueva === actual) return;
  estado.carrito = establecerCantidad(estado.carrito, producto, nueva);
  estado.almacen.guardar(estado.carrito);
  actualizarProducto(id);
  actualizarBarra();
}

function aplicarFiltro() {
  const hayFiltro = estado.texto.trim() !== '' || estado.categoria !== null;
  const coincidentes = filtrarProductos(estado.productos, { texto: estado.texto, categoria: estado.categoria });
  const ids = new Set(coincidentes.map((p) => p.id));
  for (const [id, fila] of filas) fila.li.hidden = !ids.has(id);

  for (const { chip, categoria } of refs.chips) chip.setAttribute('aria-pressed', String(categoria === estado.categoria));
  refs.carriles.hidden = hayFiltro;
  refs.sinResultados.hidden = coincidentes.length > 0;
  refs.contador.textContent = `${coincidentes.length} ${coincidentes.length === 1 ? 'producto' : 'productos'}`;

  // Los controles se sincronizan una vez al armar y cada vez que cambia el carrito.
  if (!refs.sincronizado) {
    for (const p of estado.productos) actualizarProducto(p.id);
    refs.sincronizado = true;
  }
}

/* ---------- Pantalla de pedido ---------- */

const SEGUNDOS_DESHACER = 10;

function construirPedido() {
  const general = estado.modo === 'general';

  const volver = h('button', { clase: 'btn-volver', type: 'button', 'aria-label': 'Volver a la vitrina' }, [flechaAtras()]);
  volver.addEventListener('click', volverAInicio);
  const cabecera = h('header', { clase: 'cabecera' }, [
    h('div', { clase: 'interior cabecera-fila' }, [volver, h('h1', { texto: 'Tu pedido', id: 'titulo-pedido', tabindex: '-1' })]),
  ]);

  // Lista y total.
  refs.lineas = h('ul', { clase: 'lineas' });
  refs.total = h('p', { clase: 'total-importe', 'aria-live': 'polite' });
  const bloqueLista = h('section', { clase: 'seccion', 'aria-labelledby': 'titulo-lineas' }, [
    h('h2', { clase: 'seccion-titulo', id: 'titulo-lineas', texto: 'Lo que elegiste' }),
    refs.lineas,
    h('div', { clase: 'total-bloque' }, [h('p', { clase: 'total-etiqueta', texto: 'Total' }), refs.total]),
    h('p', {
      clase: 'nota',
      texto: general
        ? 'Precios del catálogo. Tu preventista confirma disponibilidad y entrega.'
        : 'Los precios son los de tu lista. Distribuidora Alberdi confirma disponibilidad y entrega.',
    }),
  ]);

  // Observaciones.
  refs.aclaracion = h('textarea', {
    id: 'aclaracion',
    rows: '3',
    maxlength: '1000',
    placeholder: 'Ej.: entregar después de las 10',
  });
  if (general) {
    refs.nombre = h('input', { id: 'nombre', type: 'text', maxlength: '60', autocomplete: 'organization', enterkeyhint: 'next' });
    for (const campo of [refs.nombre, refs.aclaracion]) campo.addEventListener('input', actualizarBoton);
  }
  const bloqueDatos = h('section', { clase: 'seccion', 'aria-labelledby': 'titulo-datos' }, [
    h('h2', { clase: 'seccion-titulo', id: 'titulo-datos', texto: general ? 'Tus datos' : 'Observaciones' }),
    general && h('div', { clase: 'campo' }, [h('label', { for: 'nombre', texto: 'Tu nombre o el de tu negocio' }), refs.nombre]),
    h('div', { clase: 'campo' }, [h('label', { for: 'aclaracion', texto: 'Algo que debamos saber (opcional)' }), refs.aclaracion]),
  ]);

  refs.conPedido = h('div', {}, [bloqueLista, bloqueDatos]);

  // Pedido vacío.
  const volverVacio = h('button', { clase: 'btn-primario', type: 'button', texto: 'Volver a la vitrina' });
  volverVacio.addEventListener('click', volverAInicio);
  refs.vacio = h('div', { clase: 'vacio', hidden: true }, [h('p', { texto: 'Tu pedido está vacío' }), volverVacio]);

  // Pie fijo: deshacer, aviso de largo, botón de WhatsApp.
  const botonDeshacer = h('button', { clase: 'btn-deshacer', type: 'button', texto: 'Deshacer' });
  botonDeshacer.addEventListener('click', deshacerQuitar);
  refs.deshacerTexto = h('span');
  refs.deshacer = h('div', { clase: 'deshacer', role: 'status', hidden: true }, [refs.deshacerTexto, botonDeshacer]);
  refs.botonDeshacer = botonDeshacer;

  refs.error = h('p', { clase: 'aviso-largo', role: 'alert', hidden: true });
  if (general) {
    refs.enviar = h('a', { clase: 'btn-enviar', target: '_blank', rel: 'noopener noreferrer', texto: 'Enviar pedido por WhatsApp' });
  } else {
    refs.enviar = h('button', { clase: 'btn-enviar', type: 'button', texto: 'Confirmar pedido' });
    refs.enviar.addEventListener('click', confirmar);
  }
  refs.notaEnvio = h('p', {
    clase: 'nota-envio',
    texto: general
      ? `Se abre WhatsApp con tu pedido listo para mandarle a ${estado.vendedor || 'tu preventista'}. Vos solo lo enviás.`
      : 'Tu pedido llega directo a Distribuidora Alberdi. Te confirmamos disponibilidad y entrega.',
  });
  refs.grupoEnvio = h('div', {}, [refs.error, refs.enviar, refs.notaEnvio]);

  // Pedido recibido.
  refs.exitoDetalle = h('p');
  const otroPedido = h('button', { clase: 'btn-primario', type: 'button', texto: 'Volver al catálogo' });
  otroPedido.addEventListener('click', () => {
    estado.exito = null;
    volverAInicio();
  });
  refs.exito = h('div', { clase: 'vacio', role: 'status', hidden: true }, [
    h('h2', { texto: '¡Recibimos tu pedido!' }),
    refs.exitoDetalle,
    h('p', { texto: 'Queda pendiente de confirmación de disponibilidad y entrega.' }),
    otroPedido,
  ]);

  const pie = h('div', { clase: 'barra' }, [h('div', { clase: 'interior' }, [refs.deshacer, refs.grupoEnvio])]);
  refs.pie = pie;

  refs.pedido = h('div', { clase: 'pantalla', id: 'pantalla-pedido', hidden: true }, [
    cabecera,
    h('main', { clase: 'contenido' }, [h('div', { clase: 'interior' }, [refs.conPedido, refs.vacio, refs.exito])]),
    pie,
  ]);
  return refs.pedido;
}

function crearLinea({ producto, cantidad, subtotal }) {
  const quitar = h('button', {
    clase: 'btn-quitar',
    type: 'button',
    texto: 'Quitar',
    'aria-label': `Quitar ${producto.nombre} del pedido`,
  });
  quitar.addEventListener('click', () => quitarDelPedido(producto.id));
  return h('li', { clase: 'linea' }, [
    h('div', { clase: 'linea-info' }, [
      h('h3', { clase: 'linea-nombre', texto: producto.nombre }),
      h('p', { clase: 'linea-detalle', texto: detalleLinea(producto, cantidad) }),
    ]),
    h('p', { clase: 'linea-subtotal', texto: formatearPrecio(subtotal) }),
    quitar,
  ]);
}

function renderPedido() {
  const lineas = lineasDelPedido(estado.carrito, estado.porId);
  const vacio = lineas.length === 0 && !estado.pendiente;
  const exito = Boolean(estado.exito);
  refs.lineas.replaceChildren(...lineas.map(crearLinea));
  refs.total.textContent = formatearPrecio(calcularTotal(lineas));
  refs.conPedido.hidden = vacio || exito;
  refs.vacio.hidden = !vacio || exito;
  refs.exito.hidden = !exito;
  refs.grupoEnvio.hidden = vacio || exito;
  actualizarBoton();
  actualizarPie();
}

/** El pie fijo solo se ve si hay algo para enviar o un aviso de "Deshacer" pendiente. */
function actualizarPie() {
  refs.pie.hidden = refs.grupoEnvio.hidden && refs.deshacer.hidden;
}

/** Catálogo general: arma el mensaje y deja el enlace de WhatsApp listo (o explica qué falta). */
function actualizarEnlaceWhatsApp() {
  const lineas = lineasDelPedido(estado.carrito, estado.porId);
  const nombre = refs.nombre.value.trim();
  const { texto, excedeLimite } = mensajeGeneral({
    lineas,
    codigos: estado.codigos,
    vendedor: estado.vendedor,
    nombre,
    aclaracion: refs.aclaracion.value,
  });
  const url = lineas.length && nombre && !excedeLimite ? urlWhatsApp(estado.catalogo.comercio.whatsapp, texto) : null;
  refs.error.textContent = excedeLimite
    ? 'Tu pedido es demasiado largo para un solo mensaje de WhatsApp. Mandalo en dos partes.'
    : 'Escribí tu nombre o el de tu negocio para enviar el pedido.';
  refs.error.hidden = Boolean(url) || lineas.length === 0;
  if (url) {
    refs.enviar.setAttribute('href', url);
    refs.enviar.removeAttribute('aria-disabled');
    refs.enviar.removeAttribute('role');
    refs.enviar.classList.remove('deshabilitado');
  } else {
    refs.enviar.removeAttribute('href');
    refs.enviar.setAttribute('role', 'link');
    refs.enviar.setAttribute('aria-disabled', 'true');
    refs.enviar.classList.add('deshabilitado');
  }
}

function actualizarBoton() {
  if (estado.modo === 'general') return actualizarEnlaceWhatsApp();
  refs.enviar.disabled = estado.enviando;
  refs.enviar.textContent = estado.enviando
    ? 'Enviando…'
    : estado.pendiente
      ? 'Reintentar confirmación'
      : 'Confirmar pedido';
  refs.aclaracion.disabled = estado.enviando || Boolean(estado.pendiente);
  if (estado.pendiente && !estado.enviando && refs.error.hidden) {
    refs.error.textContent = 'Tu pedido se envió pero no pudimos confirmar que llegó. Tocá "Reintentar confirmación": no se va a duplicar.';
    refs.error.hidden = false;
  }
}

async function confirmar() {
  if (estado.enviando) return;
  if (!estado.pendiente) {
    const lineas = lineasDelPedido(estado.carrito, estado.porId);
    const items = itemsDelPedido(lineas, estado.precios);
    if (items.length === 0) return;
    estado.pendiente = {
      p_solicitud_id: crypto.randomUUID(),
      p_items: items,
      p_observacion: refs.aclaracion.value.trim(),
    };
    guardarPendiente();
  }
  estado.enviando = true;
  refs.error.hidden = true;
  actualizarBoton();
  try {
    const resultado = await confirmarPedido(estado.token, estado.pendiente);
    estado.pendiente = null;
    guardarPendiente();
    estado.carrito = [];
    estado.almacen.guardar(estado.carrito);
    refs.aclaracion.value = '';
    for (const id of estado.porId.keys()) actualizarProducto(id);
    actualizarBarra();
    const total = Math.round(Number(resultado?.total ?? 0) * 100);
    estado.exito = resultado;
    refs.exitoDetalle.textContent = `Total: ${formatearPrecio(total)}`;
  } catch (error) {
    const tipo = error?.tipo ?? 'incierto';
    if (tipo !== 'incierto') {
      estado.pendiente = null;
      guardarPendiente();
    }
    refs.error.textContent = error?.mensaje ?? 'No se pudo enviar el pedido. Volvé a intentar.';
    refs.error.hidden = false;
  } finally {
    estado.enviando = false;
    renderPedido();
  }
}

function quitarDelPedido(id) {
  if (estado.pendiente || estado.enviando) return;
  const producto = estado.porId.get(id);
  const cantidad = cantidadEnCarrito(estado.carrito, id);
  if (!producto || cantidad === 0) return;
  estado.carrito = establecerCantidad(estado.carrito, producto, 0);
  estado.almacen.guardar(estado.carrito);
  actualizarProducto(id);
  actualizarBarra();
  renderPedido();
  mostrarDeshacer(producto, cantidad);
}

function mostrarDeshacer(producto, cantidad) {
  clearTimeout(estado.temporizadorDeshacer);
  estado.deshacer = { id: producto.id, cantidad };
  refs.deshacerTexto.textContent = `Quitaste ${producto.nombre} · `;
  refs.deshacer.hidden = false;
  actualizarPie();
  refs.botonDeshacer.focus({ preventScroll: true });
  estado.temporizadorDeshacer = setTimeout(ocultarDeshacer, SEGUNDOS_DESHACER * 1000);
}

function ocultarDeshacer() {
  clearTimeout(estado.temporizadorDeshacer);
  estado.deshacer = null;
  refs.deshacer.hidden = true;
  actualizarPie();
}

function deshacerQuitar() {
  const pendiente = estado.deshacer;
  if (!pendiente) return;
  const producto = estado.porId.get(pendiente.id);
  ocultarDeshacer();
  if (!producto) return;
  estado.carrito = establecerCantidad(estado.carrito, producto, pendiente.cantidad);
  estado.almacen.guardar(estado.carrito);
  actualizarProducto(producto.id);
  actualizarBarra();
  renderPedido();
  [...refs.lineas.querySelectorAll('.btn-quitar')].at(-1)?.focus({ preventScroll: true });
}

iniciar();
