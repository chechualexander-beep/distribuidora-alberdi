// Vitrina — núcleo puro: sin DOM, sin red, sin efectos secundarios.
// Todo el dinero va en centavos enteros y los kilos en gramos enteros.

/* ========================================================================
 * Tema
 * ====================================================================== */

export const TEMAS = Object.freeze(['verde', 'rojo', 'azul', 'ambar', 'alberdi']);
export const TEMA_POR_DEFECTO = 'verde';

/** Devuelve un tema válido; si falta o es inválido, "verde". */
export function resolverTema(valor) {
  return typeof valor === 'string' && TEMAS.includes(valor) ? valor : TEMA_POR_DEFECTO;
}

/* ========================================================================
 * Dinero (es-AR)
 * ====================================================================== */

/** "$ 1.200" para pesos exactos y "$ 1.250,50" cuando hay centavos. */
export function formatearPrecio(centavos) {
  if (!Number.isSafeInteger(centavos) || centavos < 0) {
    throw new TypeError('El precio debe ser un entero de centavos mayor o igual a 0');
  }
  const pesos = Math.floor(centavos / 100);
  const resto = centavos % 100;
  const conMiles = String(pesos).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return resto === 0
    ? `$ ${conMiles}`
    : `$ ${conMiles},${String(resto).padStart(2, '0')}`;
}

/**
 * Subtotal de una línea en centavos enteros.
 * - unidad: precio * cantidad.
 * - kg: Math.round(precio * gramos / 1000), hecho con enteros (sin flotantes).
 */
export function calcularSubtotal(precioCentavos, unidad, cantidad) {
  if (unidad === 'kg') {
    const bruto = precioCentavos * cantidad;
    const cociente = Math.floor(bruto / 1000);
    const resto = bruto - cociente * 1000;
    return resto >= 500 ? cociente + 1 : cociente;
  }
  return precioCentavos * cantidad;
}

/** Total = suma de subtotales ya redondeados. */
export function calcularTotal(lineas) {
  let total = 0;
  for (const l of lineas) total += l.subtotal;
  return total;
}

/* ========================================================================
 * Cantidades
 * ====================================================================== */

/** Unidades: paso 1, tope 9999 (distribuidora). Kilos: gramos, paso 250, tope 10 kg. */
export const LIMITES_CANTIDAD = Object.freeze({
  unidad: Object.freeze({ paso: 1, tope: 9999 }),
  kg: Object.freeze({ paso: 250, tope: 10000 }),
});

function limitesDe(unidad) {
  return LIMITES_CANTIDAD[unidad === 'kg' ? 'kg' : 'unidad'];
}

export function masCantidad(unidad, actual) {
  const { paso, tope } = limitesDe(unidad);
  return Math.min(tope, actual + paso);
}

export function menosCantidad(unidad, actual) {
  const { paso } = limitesDe(unidad);
  return Math.max(0, actual - paso);
}

/**
 * Lleva una cantidad cualquiera a un valor permitido: entero, múltiplo del
 * paso y dentro del tope. Devuelve 0 si no es utilizable.
 */
export function normalizarCantidad(unidad, valor) {
  if (!Number.isFinite(valor) || valor <= 0) return 0;
  const { paso, tope } = limitesDe(unidad);
  const entero = Math.floor(valor);
  const enPasos = Math.floor(entero / paso) * paso;
  return Math.min(tope, enPasos);
}

const FRACCIONES = Object.freeze({ 250: '¼', 500: '½', 750: '¾' });

/** "3" para unidades; "¼ kg", "½ kg", "¾ kg", "1 kg", "1 ¼ kg" para kilos. */
export function formatearCantidad(unidad, cantidad) {
  if (unidad !== 'kg') return String(cantidad);
  const kilos = Math.floor(cantidad / 1000);
  const gramos = cantidad % 1000;
  if (gramos === 0) return `${kilos} kg`;
  const fraccion = FRACCIONES[gramos];
  if (!fraccion) return `${cantidad} g`;
  return kilos === 0 ? `${fraccion} kg` : `${kilos} ${fraccion} kg`;
}

/** Detalle de una línea del pedido: "2 unidades × $ 1.200" / "¼ kg × $ 8.000 el kilo". */
export function detalleLinea(producto, cantidad) {
  const precio = formatearPrecio(producto.precio_centavos);
  if (producto.unidad === 'kg') {
    return `${formatearCantidad('kg', cantidad)} × ${precio} el kilo`;
  }
  return `${cantidad} ${cantidad === 1 ? 'unidad' : 'unidades'} × ${precio}`;
}

/* ========================================================================
 * Fecha (sin zonas horarias)
 * ====================================================================== */

/** true si es una fecha de calendario real con forma AAAA-MM-DD. */
export function esFechaValida(texto) {
  if (typeof texto !== 'string') return false;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto);
  if (!m) return false;
  const anio = Number(m[1]);
  const mes = Number(m[2]);
  const dia = Number(m[3]);
  if (anio < 1900 || mes < 1 || mes > 12 || dia < 1) return false;
  const bisiesto = (anio % 4 === 0 && anio % 100 !== 0) || anio % 400 === 0;
  const diasDelMes = [31, bisiesto ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return dia <= diasDelMes[mes - 1];
}

/** "2026-11-12" → "12/11/2026", partiendo el texto (no usa Date). */
export function formatearFecha(texto) {
  if (!esFechaValida(texto)) throw new TypeError('Fecha inválida (se espera AAAA-MM-DD)');
  const [anio, mes, dia] = texto.split('-');
  return `${dia}/${mes}/${anio}`;
}

/* ========================================================================
 * Búsqueda, categorías y carriles
 * ====================================================================== */

/** Minúsculas y sin tildes/diacríticos, para comparar texto. */
export function normalizarTexto(texto) {
  return String(texto ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim();
}

const cacheBusqueda = new WeakMap();

function textoBuscable(producto) {
  let texto = cacheBusqueda.get(producto);
  if (texto === undefined) {
    texto = normalizarTexto(`${producto.nombre} ${producto.descripcion ?? ''} ${producto.categoria ?? ''}`);
    cacheBusqueda.set(producto, texto);
  }
  return texto;
}

/**
 * Filtra por texto (todas las palabras deben aparecer, sin tildes ni
 * mayúsculas) y por categoría (null = todas). Mantiene el orden original.
 */
export function filtrarProductos(productos, { texto = '', categoria = null } = {}) {
  const palabras = normalizarTexto(texto).split(/\s+/).filter(Boolean);
  return productos.filter((p) => {
    if (categoria !== null && p.categoria !== categoria) return false;
    if (palabras.length === 0) return true;
    const texto = textoBuscable(p);
    return palabras.every((palabra) => texto.includes(palabra));
  });
}

/** Categorías únicas en orden de aparición (la UI agrega "Todos" al principio). */
export function obtenerCategorias(productos) {
  const vistas = new Set();
  for (const p of productos) vistas.add(p.categoria);
  return [...vistas];
}

/** Oferta: tiene precio anterior y es mayor que el actual. */
export function esOferta(producto) {
  return (
    Number.isSafeInteger(producto.precio_anterior_centavos) &&
    producto.precio_anterior_centavos > producto.precio_centavos
  );
}

export function productosNovedades(productos) {
  return productos.filter((p) => p.destacado === true);
}

export function productosOfertas(productos) {
  return productos.filter(esOferta);
}

/* ========================================================================
 * Miniaturas sin foto: iniciales y color determinista
 * ====================================================================== */

export const CANTIDAD_PAREJAS_INICIALES = 4;

/** Dos letras: iniciales de las dos primeras palabras (o las dos primeras letras si es una sola). */
export function obtenerIniciales(nombre) {
  const palabras = String(nombre ?? '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((p) => Array.from(p).filter((c) => /[\p{L}\p{N}]/u.test(c)))
    .filter((letras) => letras.length > 0);
  if (palabras.length === 0) return '?';
  const letras =
    palabras.length === 1 ? palabras[0].slice(0, 2) : [palabras[0][0], palabras[1][0]];
  return letras.join('').toLocaleUpperCase('es-AR');
}

/** Índice 0..3 de la pareja fondo/letra (se define en CSS), elegido por hash del id (FNV-1a). */
export function indiceParejaIniciales(id) {
  let h = 0x811c9dc5;
  for (const unidadDeCodigo of String(id)) {
    for (let i = 0; i < unidadDeCodigo.length; i++) {
      h ^= unidadDeCodigo.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
  }
  return (h >>> 0) % CANTIDAD_PAREJAS_INICIALES;
}

/* ========================================================================
 * Validación del catálogo (formato 1)
 * ====================================================================== */

export const FORMATO_CATALOGO = 1;
export const MAX_PRODUCTOS = 2000;
/** $ 10.000.000: tope de cordura para un precio (en centavos). */
export const PRECIO_MAXIMO_CENTAVOS = 1_000_000_000;

const MAX_ERRORES = 50;
const REGEX_SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const REGEX_ID_PRODUCTO = /^[A-Za-z0-9._-]{1,64}$/;
const REGEX_WHATSAPP = /^[1-9]\d{7,14}$/;
const REGEX_MINIATURA = /^[A-Za-z0-9][A-Za-z0-9._/-]*\.(?:jpe?g|png|webp|gif|avif|svg)$/i;
// eslint-disable-next-line no-control-regex
const REGEX_CONTROL = /[\u0000-\u001f\u007f-\u009f]/;

/** Número de WhatsApp: solo dígitos, con código de país (8 a 15 dígitos, sin 0 inicial). */
export function esWhatsappValido(valor) {
  return typeof valor === 'string' && REGEX_WHATSAPP.test(valor);
}

/** Slug de comercio: minúsculas, números y guiones. */
export function esSlugValido(valor) {
  return typeof valor === 'string' && valor.length <= 64 && REGEX_SLUG.test(valor);
}

/**
 * Una miniatura es segura solo si es una ruta relativa dentro de la carpeta del
 * comercio: sin "..", sin "//", sin esquema ("javascript:", "http:"), sin "%",
 * sin "\", sin "/" inicial y con extensión de imagen.
 */
export function esMiniaturaSegura(ruta) {
  if (typeof ruta !== 'string' || ruta.length > 200) return false;
  if (!REGEX_MINIATURA.test(ruta)) return false;
  if (ruta.includes('..') || ruta.includes('//') || ruta.includes('/.')) return false;
  return true;
}

function esObjetoPlano(valor) {
  return valor !== null && typeof valor === 'object' && !Array.isArray(valor);
}

/** Texto obligatorio u opcional: recortado, sin caracteres de control y con largo máximo. */
function leerTexto(origen, campo, ruta, { max, requerido }, errores) {
  const valor = origen[campo];
  if (valor === undefined || valor === null) {
    if (requerido) errores.push({ ruta: `${ruta}.${campo}`, mensaje: 'falta este campo' });
    return undefined;
  }
  if (typeof valor !== 'string') {
    errores.push({ ruta: `${ruta}.${campo}`, mensaje: 'tiene que ser un texto' });
    return undefined;
  }
  const texto = valor.trim();
  if (texto === '') {
    if (requerido) errores.push({ ruta: `${ruta}.${campo}`, mensaje: 'no puede estar vacío' });
    return undefined;
  }
  if (REGEX_CONTROL.test(texto)) {
    errores.push({ ruta: `${ruta}.${campo}`, mensaje: 'tiene caracteres no permitidos' });
    return undefined;
  }
  if (Array.from(texto).length > max) {
    errores.push({ ruta: `${ruta}.${campo}`, mensaje: `es demasiado largo (máximo ${max} caracteres)` });
    return undefined;
  }
  return texto;
}

function leerBooleano(origen, campo, ruta, porDefecto, errores) {
  const valor = origen[campo];
  if (valor === undefined || valor === null) return porDefecto;
  if (typeof valor !== 'boolean') {
    errores.push({ ruta: `${ruta}.${campo}`, mensaje: 'tiene que ser true o false' });
    return porDefecto;
  }
  return valor;
}

function leerCentavos(origen, campo, ruta, requerido, errores) {
  const valor = origen[campo];
  if (valor === undefined || valor === null) {
    if (requerido) errores.push({ ruta: `${ruta}.${campo}`, mensaje: 'falta este campo' });
    return undefined;
  }
  if (!Number.isSafeInteger(valor) || valor < 1 || valor > PRECIO_MAXIMO_CENTAVOS) {
    errores.push({
      ruta: `${ruta}.${campo}`,
      mensaje: `tiene que ser un número entero de centavos entre 1 y ${PRECIO_MAXIMO_CENTAVOS} (ejemplo: $ 1.200 se escribe 120000)`,
    });
    return undefined;
  }
  return valor;
}

/* ------------------------------------------------------------------------
 * Horarios de atención
 * ---------------------------------------------------------------------- */

export const DIAS_SEMANA = Object.freeze(['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo']);
const ETIQUETAS_DIA = Object.freeze({
  lunes: 'Lunes',
  martes: 'Martes',
  miercoles: 'Miércoles',
  jueves: 'Jueves',
  viernes: 'Viernes',
  sabado: 'Sábado',
  domingo: 'Domingo',
});
export const MAX_TRAMOS_POR_DIA = 3;
export const MAX_NOTA_HORARIOS = 120;
const REGEX_TRAMO = /^(\d{2}):(\d{2})-(\d{2}):(\d{2})$/;

function aMinutos(hh, mm, permite24) {
  const h = Number(hh);
  const m = Number(mm);
  if (m > 59) return null;
  if (h === 24) return m === 0 && permite24 ? 1440 : null;
  return h <= 23 ? h * 60 + m : null;
}

/** Interpreta "HH:MM-HH:MM" (24 hs) como { desde, hasta } en minutos; null si el formato es inválido. */
export function leerTramo(texto) {
  if (typeof texto !== 'string') return null;
  const m = REGEX_TRAMO.exec(texto);
  if (!m) return null;
  const desde = aMinutos(m[1], m[2], false);
  const hasta = aMinutos(m[3], m[4], true); // "24:00" solo vale como hasta
  return desde === null || hasta === null ? null : { desde, hasta };
}

/**
 * Valida el bloque "horarios". Devuelve { horarios } con los 7 días normalizados
 * (día ausente = []) o { errores: [{ ruta, mensaje }] }.
 */
export function validarHorarios(valor, ruta = 'comercio.horarios') {
  if (!esObjetoPlano(valor)) {
    return { errores: [{ ruta, mensaje: 'tiene que ser un objeto con los días de la semana' }] };
  }
  const errores = [];
  for (const clave of Object.keys(valor)) {
    if (!DIAS_SEMANA.includes(clave)) {
      errores.push({
        ruta: `${ruta}.${clave}`,
        mensaje: 'día inválido: usá lunes, martes, miercoles, jueves, viernes, sabado o domingo (sin tildes y en minúscula)',
      });
    }
  }

  const horarios = {};
  for (const dia of DIAS_SEMANA) {
    const rutaDia = `${ruta}.${dia}`;
    const tramos = valor[dia];
    horarios[dia] = [];
    if (tramos === undefined || tramos === null) continue;
    if (!Array.isArray(tramos)) {
      errores.push({ ruta: rutaDia, mensaje: 'tiene que ser una lista de tramos "HH:MM-HH:MM" (vacía si ese día está cerrado)' });
      continue;
    }
    if (tramos.length > MAX_TRAMOS_POR_DIA) {
      errores.push({ ruta: rutaDia, mensaje: `hay ${tramos.length} tramos y el máximo por día es ${MAX_TRAMOS_POR_DIA}` });
      continue;
    }
    let finAnterior = null;
    tramos.forEach((texto, i) => {
      const rutaTramo = `${rutaDia}[${i}]`;
      const tramo = leerTramo(texto);
      if (!tramo) {
        errores.push({ ruta: rutaTramo, mensaje: 'formato inválido: usá "HH:MM-HH:MM" en 24 hs (ejemplo: "08:00-12:00")' });
      } else if (tramo.desde === tramo.hasta) {
        errores.push({ ruta: rutaTramo, mensaje: 'desde y hasta no pueden ser iguales' });
      } else if (tramo.hasta < tramo.desde && i !== tramos.length - 1) {
        errores.push({ ruta: rutaTramo, mensaje: 'un tramo que cruza la medianoche solo puede ser el último del día' });
      } else if (finAnterior !== null && tramo.desde < finAnterior) {
        errores.push({ ruta: rutaTramo, mensaje: 'se pisa con el tramo anterior o está fuera de orden' });
      } else {
        finAnterior = tramo.hasta;
        horarios[dia].push(texto);
      }
    });
  }
  return errores.length > 0 ? { errores } : { horarios };
}

function formatearHora(minutos) {
  return `${Math.floor(minutos / 60)}:${String(minutos % 60).padStart(2, '0')}`;
}

/** "08:00-12:00" → "8:00 a 12:00" (sin cero a la izquierda en la hora). */
export function formatearTramo(texto) {
  const tramo = leerTramo(texto);
  if (!tramo) throw new TypeError('Tramo inválido (se espera HH:MM-HH:MM)');
  return `${formatearHora(tramo.desde)} a ${formatearHora(tramo.hasta)}`;
}

/** "8:00 a 12:00 y 17:00 a 21:00", "Las 24 hs" (00:00-24:00) o "Cerrado" (lista vacía). */
export function formatearHorarioDia(tramos) {
  if (!Array.isArray(tramos) || tramos.length === 0) return 'Cerrado';
  if (tramos.length === 1 && tramos[0] === '00:00-24:00') return 'Las 24 hs';
  const partes = tramos.map(formatearTramo);
  if (partes.length === 1) return partes[0];
  return `${partes.slice(0, -1).join(', ')} y ${partes[partes.length - 1]}`;
}

/** Índice de Date.getDay() (domingo = 0) → posición en la lista que empieza en lunes; -1 si no es válido. */
function posicionEnSemana(indiceDia) {
  return Number.isInteger(indiceDia) && indiceDia >= 0 && indiceDia <= 6 ? (indiceDia + 6) % 7 : -1;
}

/** Siete filas lunes→domingo para mostrar; `indiceDia` es el de Date.getDay() (domingo = 0). */
export function filasHorarios(horarios, indiceDia) {
  const hoy = posicionEnSemana(indiceDia);
  return DIAS_SEMANA.map((dia, i) => ({
    dia: ETIQUETAS_DIA[dia],
    texto: formatearHorarioDia(horarios[dia]),
    cerrado: !horarios[dia] || horarios[dia].length === 0,
    esHoy: i === hoy,
  }));
}

/** "Hoy: 8:00 a 12:00 y 17:00 a 21:00" / "Hoy: cerrado"; null si el día no se puede determinar. */
export function textoHoy(horarios, indiceDia) {
  const posicion = posicionEnSemana(indiceDia);
  if (posicion < 0) return null;
  const texto = formatearHorarioDia(horarios[DIAS_SEMANA[posicion]]);
  if (texto === 'Cerrado') return 'Hoy: cerrado';
  if (texto === 'Las 24 hs') return 'Hoy: las 24 hs';
  return `Hoy: ${texto}`;
}

function validarComercio(origen, errores, avisos, { whatsappOpcional = false } = {}) {
  if (!esObjetoPlano(origen)) {
    errores.push({ ruta: 'comercio', mensaje: 'falta el bloque "comercio" o no es un objeto' });
    return undefined;
  }
  const ruta = 'comercio';
  const comercio = {};

  if (typeof origen.id !== 'string' || !esSlugValido(origen.id)) {
    errores.push({
      ruta: 'comercio.id',
      mensaje: 'tiene que ser un identificador en minúsculas, números y guiones (ejemplo: "kiosco-ejemplo")',
    });
  } else {
    comercio.id = origen.id;
  }

  comercio.nombre = leerTexto(origen, 'nombre', ruta, { max: 80, requerido: true }, errores);

  if (whatsappOpcional && (origen.whatsapp === undefined || origen.whatsapp === null)) {
    // Alberdi: el pedido entra directo a la distribuidora, no sale por WhatsApp.
  } else if (!esWhatsappValido(origen.whatsapp)) {
    errores.push({
      ruta: 'comercio.whatsapp',
      mensaje: 'tiene que ser un texto de solo dígitos con código de país (ejemplo: "5491112345678")',
    });
  } else {
    comercio.whatsapp = origen.whatsapp;
  }

  // Horarios: opcionales. Si el bloque es inválido NO se rechaza el catálogo: se ignora
  // solo ese bloque (o solo la nota) y se avisa. El campo viejo "horario" ya no se usa.
  if (origen.horarios !== undefined && origen.horarios !== null) {
    const lectura = validarHorarios(origen.horarios);
    if (lectura.horarios) {
      comercio.horarios = lectura.horarios;
      const erroresNota = [];
      const nota = leerTexto(origen, 'horarios_nota', ruta, { max: MAX_NOTA_HORARIOS, requerido: false }, erroresNota);
      if (nota !== undefined) comercio.horarios_nota = nota;
      avisos.push(...erroresNota);
    } else {
      avisos.push(...lectura.errores);
    }
  }

  if (!esFechaValida(origen.actualizado)) {
    errores.push({
      ruta: 'comercio.actualizado',
      mensaje: 'tiene que ser una fecha real con formato AAAA-MM-DD (ejemplo: "2026-11-12")',
    });
  } else {
    comercio.actualizado = origen.actualizado;
  }

  comercio.tema = resolverTema(origen.tema);
  return comercio;
}

function validarProducto(origen, indice, idsVistos, errores) {
  const ruta = `productos[${indice}]`;
  if (!esObjetoPlano(origen)) {
    errores.push({ ruta, mensaje: 'tiene que ser un objeto' });
    return undefined;
  }
  const producto = {};

  if (typeof origen.id !== 'string' || !REGEX_ID_PRODUCTO.test(origen.id)) {
    errores.push({
      ruta: `${ruta}.id`,
      mensaje: 'tiene que ser un texto de 1 a 64 caracteres: letras, números, punto, guion o guion bajo',
    });
  } else if (idsVistos.has(origen.id)) {
    errores.push({ ruta: `${ruta}.id`, mensaje: `el id "${origen.id}" está repetido` });
  } else {
    idsVistos.add(origen.id);
    producto.id = origen.id;
  }

  producto.nombre = leerTexto(origen, 'nombre', ruta, { max: 120, requerido: true }, errores);
  const descripcion = leerTexto(origen, 'descripcion', ruta, { max: 200, requerido: false }, errores);
  if (descripcion !== undefined) producto.descripcion = descripcion;
  producto.categoria = leerTexto(origen, 'categoria', ruta, { max: 40, requerido: true }, errores);

  if (origen.unidad !== 'unidad' && origen.unidad !== 'kg') {
    errores.push({ ruta: `${ruta}.unidad`, mensaje: 'tiene que ser "unidad" o "kg"' });
  } else {
    producto.unidad = origen.unidad;
  }

  producto.precio_centavos = leerCentavos(origen, 'precio_centavos', ruta, true, errores);
  const anterior = leerCentavos(origen, 'precio_anterior_centavos', ruta, false, errores);
  // Solo cuenta como oferta si el precio anterior es mayor; si no, se ignora.
  if (anterior !== undefined && producto.precio_centavos !== undefined && anterior > producto.precio_centavos) {
    producto.precio_anterior_centavos = anterior;
  }

  // Una miniatura insegura no invalida el catálogo: se ignora y se muestran las iniciales.
  if (esMiniaturaSegura(origen.miniatura)) producto.miniatura = origen.miniatura;

  producto.destacado = leerBooleano(origen, 'destacado', ruta, false, errores);
  producto.visible = leerBooleano(origen, 'visible', ruta, true, errores);
  return producto;
}

/**
 * Valida un catálogo (formato 1). Estricto: ignora campos desconocidos y rechaza
 * lo inválido con mensajes claros. Devuelve { ok: true, catalogo } con datos
 * normalizados (y `avisos`: partes opcionales ignoradas, como horarios inválidos),
 * o { ok: false, errores: [{ ruta, mensaje }] }.
 */
export function validarCatalogo(json, opciones = {}) {
  const errores = [];
  if (!esObjetoPlano(json)) {
    return { ok: false, errores: [{ ruta: '(raíz)', mensaje: 'el catálogo tiene que ser un objeto JSON' }] };
  }
  if (json.formato !== FORMATO_CATALOGO) {
    errores.push({ ruta: 'formato', mensaje: `tiene que ser ${FORMATO_CATALOGO}` });
  }

  const avisos = [];
  const comercio = validarComercio(json.comercio, errores, avisos, opciones);

  const productos = [];
  if (!Array.isArray(json.productos)) {
    errores.push({ ruta: 'productos', mensaje: 'tiene que ser una lista de productos' });
  } else if (json.productos.length === 0) {
    errores.push({ ruta: 'productos', mensaje: 'tiene que haber al menos un producto' });
  } else if (json.productos.length > MAX_PRODUCTOS) {
    errores.push({
      ruta: 'productos',
      mensaje: `hay ${json.productos.length} productos y el máximo es ${MAX_PRODUCTOS}`,
    });
  } else {
    const idsVistos = new Set();
    for (let i = 0; i < json.productos.length && errores.length < MAX_ERRORES; i++) {
      const producto = validarProducto(json.productos[i], i, idsVistos, errores);
      if (producto) productos.push(producto);
    }
  }

  if (errores.length > 0) return { ok: false, errores: errores.slice(0, MAX_ERRORES) };
  return { ok: true, catalogo: { formato: FORMATO_CATALOGO, comercio, productos }, avisos };
}

/** Texto de los errores, una línea por error (para consola/desarrollo, nunca para el cliente). */
export function describirErrores(errores) {
  return errores.map((e) => `${e.ruta}: ${e.mensaje}`).join('\n');
}

/** Productos que se muestran (visible !== false). */
export function productosVisibles(catalogo) {
  return catalogo.productos.filter((p) => p.visible !== false);
}

/* ========================================================================
 * Rutas (hash): #/  #/pedido  #/foto/<id>
 * ====================================================================== */

export const RUTA_INICIO = '#/';
export const RUTA_PEDIDO = '#/pedido';
const PREFIJO_FOTO = '#/foto/';

/** Hash del visor de foto de un producto. */
export function hashDeFoto(id) {
  return `${PREFIJO_FOTO}${encodeURIComponent(id)}`;
}

/**
 * Interpreta un hash: { tipo: 'inicio' } | { tipo: 'pedido' } | { tipo: 'foto', id }.
 * En "foto", `id` es null si el hash está mal formado (vacío, con "/" de más o mal codificado).
 */
export function rutaDesdeHash(hash) {
  const texto = typeof hash === 'string' ? hash : '';
  if (texto === RUTA_PEDIDO) return { tipo: 'pedido' };
  if (!texto.startsWith(PREFIJO_FOTO)) return { tipo: 'inicio' };
  const crudo = texto.slice(PREFIJO_FOTO.length);
  if (crudo === '' || crudo.includes('/')) return { tipo: 'foto', id: null };
  try {
    return { tipo: 'foto', id: decodeURIComponent(crudo) || null };
  } catch {
    return { tipo: 'foto', id: null };
  }
}

/**
 * Decide qué mostrar para un hash: { pantalla: 'inicio' | 'pedido', foto: producto | null, corregirA }.
 * El visor solo se muestra si el producto existe y tiene foto; si no, se vuelve al inicio
 * (`corregirA` es el hash al que hay que reemplazar la dirección actual, o null si está bien).
 * `porId` es un Map id → producto (solo visibles).
 */
export function resolverRuta(hash, porId) {
  const ruta = rutaDesdeHash(hash);
  if (ruta.tipo === 'pedido') return { pantalla: 'pedido', foto: null, corregirA: null };
  if (ruta.tipo === 'foto') {
    const producto = ruta.id === null ? undefined : porId.get(ruta.id);
    if (producto && producto.miniatura) return { pantalla: 'inicio', foto: producto, corregirA: null };
    return { pantalla: 'inicio', foto: null, corregirA: RUTA_INICIO };
  }
  return { pantalla: 'inicio', foto: null, corregirA: null };
}

/* ========================================================================
 * Carrito
 *
 * Un carrito es una lista (en orden de agregado) de { id, cantidad, precio_centavos }.
 * `precio_centavos` es una foto del precio al momento de agregar/reconciliar,
 * para poder avisar si cambió. Las funciones no mutan: devuelven un carrito nuevo.
 * ====================================================================== */

export function indexarProductos(productos) {
  const porId = new Map();
  for (const p of productos) porId.set(p.id, p);
  return porId;
}

export function cantidadEnCarrito(carrito, id) {
  const item = carrito.find((i) => i.id === id);
  return item ? item.cantidad : 0;
}

/** Fija la cantidad de un producto (normalizada). Con 0 lo saca del carrito. */
export function establecerCantidad(carrito, producto, cantidad) {
  const normalizada = normalizarCantidad(producto.unidad, cantidad);
  const sinEste = carrito.filter((i) => i.id !== producto.id);
  if (normalizada === 0) return sinEste;
  const nuevo = { id: producto.id, cantidad: normalizada, precio_centavos: producto.precio_centavos };
  const posicion = carrito.findIndex((i) => i.id === producto.id);
  if (posicion === -1) return [...sinEste, nuevo];
  const copia = carrito.slice();
  copia[posicion] = nuevo;
  return copia;
}

/** Líneas del pedido con el producto vigente y su subtotal. Ignora ids que ya no existen. */
export function lineasDelPedido(carrito, porId) {
  const lineas = [];
  for (const item of carrito) {
    const producto = porId.get(item.id);
    if (!producto) continue;
    lineas.push({
      producto,
      cantidad: item.cantidad,
      subtotal: calcularSubtotal(producto.precio_centavos, producto.unidad, item.cantidad),
    });
  }
  return lineas;
}

/** Cantidad de productos distintos en el pedido (el "N" de "Ver mi pedido · N"). */
export function cantidadDeProductos(carrito) {
  return carrito.length;
}

export const AVISO_PRECIOS = 'Algunos precios cambiaron';
export const AVISO_QUITADOS = 'Quitamos productos que ya no están';

/**
 * Pone el carrito guardado al día con el catálogo: saca productos que ya no
 * existen o no son visibles, actualiza precios y ajusta cantidades inválidas.
 * Devuelve { carrito, avisos: { preciosCambiaron, productosQuitados } }.
 */
export function reconciliarCarrito(guardado, productos) {
  const porId = indexarProductos(productos.filter((p) => p.visible !== false));
  const carrito = [];
  const vistos = new Set();
  let preciosCambiaron = false;
  let productosQuitados = false;

  for (const item of Array.isArray(guardado) ? guardado : []) {
    if (vistos.has(item.id)) continue;
    vistos.add(item.id);
    const producto = porId.get(item.id);
    if (!producto) {
      productosQuitados = true;
      continue;
    }
    const cantidad = normalizarCantidad(producto.unidad, item.cantidad);
    if (cantidad === 0) {
      productosQuitados = true;
      continue;
    }
    if (item.precio_centavos !== producto.precio_centavos) preciosCambiaron = true;
    carrito.push({ id: producto.id, cantidad, precio_centavos: producto.precio_centavos });
  }
  return { carrito, avisos: { preciosCambiaron, productosQuitados } };
}

/** Textos de los carteles a mostrar para unos avisos de reconciliación. */
export function mensajesDeAvisos(avisos) {
  const mensajes = [];
  if (avisos.preciosCambiaron) mensajes.push(AVISO_PRECIOS);
  if (avisos.productosQuitados) mensajes.push(AVISO_QUITADOS);
  return mensajes;
}

/** Clave de localStorage: "vitrina:" + id del comercio. */
export function claveCarrito(comercioId) {
  return `vitrina:${comercioId}`;
}

export function serializarCarrito(carrito) {
  return JSON.stringify({
    v: 1,
    items: carrito.map((i) => ({ id: i.id, c: i.cantidad, p: i.precio_centavos })),
  });
}

/** Lee el texto guardado; cualquier cosa rara devuelve un carrito vacío. */
export function leerCarrito(texto) {
  if (typeof texto !== 'string' || texto === '') return [];
  let datos;
  try {
    datos = JSON.parse(texto);
  } catch {
    return [];
  }
  if (!esObjetoPlano(datos) || datos.v !== 1 || !Array.isArray(datos.items)) return [];
  const carrito = [];
  for (const i of datos.items) {
    if (!esObjetoPlano(i)) continue;
    if (typeof i.id !== 'string' || !Number.isSafeInteger(i.c) || !Number.isSafeInteger(i.p)) continue;
    carrito.push({ id: i.id, cantidad: i.c, precio_centavos: i.p });
  }
  return carrito;
}

/**
 * Persistencia del carrito con respaldo en memoria. `storage` es algo con
 * getItem/setItem (localStorage) o null/undefined si no hay. Todo va en
 * try/catch: si está bloqueado o falla, el carrito sigue funcionando en memoria.
 */
export function crearAlmacen(storage, clave) {
  let memoria = null;
  let usarMemoria = !storage;
  return {
    leer() {
      if (!usarMemoria) {
        try {
          return leerCarrito(storage.getItem(clave));
        } catch {
          usarMemoria = true;
        }
      }
      return leerCarrito(memoria);
    },
    guardar(carrito) {
      const texto = serializarCarrito(carrito);
      memoria = texto;
      if (usarMemoria) return;
      try {
        storage.setItem(clave, texto);
      } catch {
        usarMemoria = true;
      }
    },
  };
}

/* ========================================================================
 * Mensaje de WhatsApp
 * ====================================================================== */

/** Largo máximo (en caracteres) del texto del mensaje, antes de codificarlo. */
export const MAX_MENSAJE = 1500;

function limpiarUnaLinea(texto) {
  return String(texto ?? '').replace(/\s+/g, ' ').trim();
}

function limpiarVariasLineas(texto) {
  return String(texto ?? '')
    .replace(/\r\n?/g, '\n')
    .replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, '')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

/**
 * Arma el texto del pedido (función pura).
 * `lineas`: [{ producto, cantidad, subtotal }]; `actualizado`: "AAAA-MM-DD".
 * Devuelve { texto, largo, excedeLimite }; nunca corta el texto.
 */
export function armarMensaje({ lineas, nombre, aclaracion, actualizado }) {
  const filas = ['Hola, quiero hacer un pedido:'];
  for (const { producto, cantidad, subtotal } of lineas) {
    const precio = formatearPrecio(subtotal);
    filas.push(
      producto.unidad === 'kg'
        ? `• ${formatearCantidad('kg', cantidad)} de ${producto.nombre} — ${precio}`
        : `• ${cantidad} × ${producto.nombre} — ${precio}`,
    );
  }
  filas.push(`Total: ${formatearPrecio(calcularTotal(lineas))}`);

  const quien = limpiarUnaLinea(nombre);
  if (quien) filas.push(`Soy ${quien}.`);
  const nota = limpiarVariasLineas(aclaracion);
  if (nota) filas.push(nota);

  filas.push(`Vi tu catálogo · precios al ${formatearFecha(actualizado)}`);
  const texto = filas.join('\n');
  return { texto, largo: texto.length, excedeLimite: texto.length > MAX_MENSAJE };
}

/** https://wa.me/{numero}?text={mensaje}. Devuelve null si el número no es válido. */
export function urlWhatsApp(numero, texto) {
  if (!esWhatsappValido(numero)) return null;
  return `https://wa.me/${numero}?text=${encodeURIComponent(texto)}`;
}
