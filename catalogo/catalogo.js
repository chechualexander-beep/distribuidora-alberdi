/* Solo clave publicable. Las tablas privadas no se consultan desde esta página. */
(() => {
  'use strict';
  const endpoint = 'https://vmbncsqapqdyffscwfwo.supabase.co/rest/v1/rpc/';
  const key = 'sb_publishable_w_nz47b753qQkzv2pr7lhA_Yl4eZsTB';
  const core = globalThis.CatalogoCore;
  const $ = id => document.getElementById(id);
  const token = new URLSearchParams(location.hash.slice(1)).get('token') || '';
  // Abrir otro enlace en la misma pestaña debe cargar el catálogo correspondiente.
  window.addEventListener('hashchange', () => location.reload());
  const storageKey = `alberdi-carrito:${token}`;
  let products = [], basket = {}, category = '', pending = null, sending = false;
  let catalogScroll = 0;
  const ownsState = state => state && state.catalogToken === token;
  function showView(view) {
    $('catalog').hidden = view !== 'catalog';
    $('review').hidden = view !== 'review';
    $('success').hidden = view !== 'success';
    $('cart-bar').hidden = view !== 'catalog' || $('shop').hidden;
    window.scrollTo(0, view === 'catalog' ? catalogScroll : 0);
  }
  // The cart is a real browser-history step. Keep the token fragment unchanged.
  const initialView = ownsState(history.state) && history.state.view === 'review' ? 'review' : 'catalog';
  history.replaceState({ catalogToken: token, view: initialView }, '', location.href);
  showView(initialView);
  window.addEventListener('popstate', event => {
    if ((new URLSearchParams(location.hash.slice(1)).get('token') || '') !== token) return;
    if ($('photo-viewer').open) $('photo-viewer').close();
    showView(ownsState(event.state) ? event.state.view : 'catalog');
    save();
  });
  try { const saved = JSON.parse(sessionStorage.getItem(storageKey) || '{}'); basket = saved.basket || {}; pending = saved.pending || null; $('notes').value = saved.notes || ''; } catch { /* Almacenamiento opcional */ }
  function save() { try { sessionStorage.setItem(storageKey, JSON.stringify({ basket, pending, notes: $('notes').value })); } catch { /* Modo privado */ } }
  function message(text, error = false) { $('status').textContent = text; $('status').classList.toggle('error', error); $('status').setAttribute('role', error ? 'alert' : 'status'); }
  async function rpc(name, payload) {
    let response;
    try { response = await fetch(endpoint + name, { method: 'POST', headers: { apikey: key, 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(20000) }); }
    catch { throw Object.assign(new Error('No pudimos confirmar la conexión. Volvé a intentar; tu pedido no se duplicará.'), { uncertain: true }); }
    let result;
    try { result = await response.json(); } catch { throw Object.assign(new Error('Respuesta incompleta. Volvé a intentar.'), { uncertain: true }); }
    if (!response.ok) throw Object.assign(new Error(result.message || 'No se pudo completar la operación.'), { expired: response.status === 410, uncertain: response.status >= 500 || response.status === 408 });
    return result;
  }
  function expired(error) { if (!error.expired) return false; $('shop').hidden = true; $('cart-bar').hidden = true; $('retry').hidden = true; return true; }
  function element(tag, className, text) { const node = document.createElement(tag); if (className) node.className = className; if (text !== undefined) node.textContent = text; return node; }
  function productRow(p) {
    const row = element('article', 'product');
    let image = element('div', 'pack', '▦'); image.setAttribute('aria-hidden', 'true');
    if (typeof p.foto_path === 'string' && /^[a-f0-9-]{36}\/[0-9]+\.jpg$/.test(p.foto_path)) {
      image = element('button', 'pack photo-button'); image.type = 'button';
      image.setAttribute('aria-label', `Ampliar foto de ${p.nombre}`);
      const photo = element('img'); photo.alt = ''; photo.loading = 'lazy'; photo.decoding = 'async';
      photo.src = endpoint.replace('/rest/v1/rpc/', '/storage/v1/object/public/productos-fotos/') + p.foto_path;
      photo.addEventListener('error', () => { image.replaceChildren(document.createTextNode('▦')); image.disabled = true; image.setAttribute('aria-label', `Foto no disponible de ${p.nombre}`); }, { once: true });
      image.addEventListener('click', () => {
        $('photo-title').textContent = p.nombre;
        $('photo-error').hidden = true;
        $('photo-large').hidden = false;
        $('photo-large').alt = p.nombre;
        $('photo-large').src = photo.src;
        $('photo-viewer').showModal();
        document.body.classList.add('viewing-photo');
      });
      image.replaceChildren(photo);
    }
    row.append(image);
    const info = element('div', 'product-info'); info.append(element('h3', 'product-name', p.nombre));
    if (p.descripcion) info.append(element('p', 'detail', p.descripcion));
    if (p.codigo) info.append(element('p', 'detail', `Código ${p.codigo}`));
    const bottom = element('div', 'product-bottom'); bottom.append(element('span', 'price', core.money(p.precio)));
    const quantity = element('div', 'quantity');
    for (const step of [-1, 1]) {
      const button = element('button', '', step === 1 ? '+' : '−'); button.type = 'button';
      button.setAttribute('aria-label', `${step === 1 ? 'Agregar' : 'Quitar'} ${p.nombre}`);
      button.disabled = sending || Boolean(pending) || (step < 0 && !basket[p.id]) || (step > 0 && basket[p.id] >= 9999);
      button.addEventListener('click', () => { basket[p.id] = Math.max(0, Math.min(9999, (basket[p.id] || 0) + step)); save(); render(); });
      quantity.append(button);
      if (step === -1) quantity.append(element('output', '', basket[p.id] || 0));
    }
    bottom.append(quantity); info.append(bottom); row.append(info); return row;
  }
  function render() {
    const visible = core.filter(products, $('search').value, category);
    $('products').replaceChildren(...visible.map(productRow));
    $('count').textContent = visible.length ? `${visible.length} ${visible.length === 1 ? 'producto' : 'productos'}` : 'No encontramos productos. Probá otra búsqueda.';
    const selected = products.filter(p => basket[p.id] > 0);
    $('cart-items').replaceChildren(...selected.map(productRow));
    const total = selected.reduce((sum, p) => sum + Math.round(p.precio * 100) * basket[p.id], 0) / 100;
    const count = selected.reduce((sum, p) => sum + basket[p.id], 0);
    $('cart-count').textContent = `Ver mi pedido · ${count}`; $('cart-total').textContent = core.money(total);
    $('total').textContent = `Total: ${core.money(total)}`;
    $('notes').disabled = sending || Boolean(pending);
    $('confirm').disabled = sending || (!selected.length && !pending);
    $('confirm').textContent = sending ? 'Enviando…' : pending ? 'Reintentar confirmación' : 'Confirmar pedido';
    $('back').disabled = sending; $('open-cart').disabled = sending;
  }
  async function load() {
    $('retry').hidden = true; message('Cargando catálogo…');
    if (!/^[a-f0-9]{64}$/.test(token)) { message('Abrí el enlace que te compartió Distribuidora Alberdi para consultar el catálogo.', true); return; }
    try {
      const result = await rpc('obtener_catalogo_cliente', { p_token: token });
      products = result.productos;
      $('validity').textContent = `Podés enviar tu pedido hasta el ${new Date(result.vence_at).toLocaleString('es-AR', {day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})}.`;
      basket = core.reconcile(products, basket);
      $('greeting').textContent = `Hola, ${result.nombre_comercio}`;
      $('categories').replaceChildren();
      for (const name of ['', ...Array.from(new Set(products.map(p => p.categoria).filter(Boolean))).sort()]) {
        const button = element('button', '', name || 'Todos'); button.type = 'button'; button.setAttribute('aria-pressed', String(category === name));
        button.addEventListener('click', () => { category = name; for (const b of $('categories').children) b.setAttribute('aria-pressed', String(b === button)); render(); });
        $('categories').append(button);
      }
      $('shop').hidden = false; $('cart-bar').hidden = $('catalog').hidden;
      message(pending ? 'Hay un pedido cuya confirmación falta verificar. Abrí tu carrito y volvé a intentar.' : '');
      render(); save();
    } catch (error) { message(error.message, true); $('retry').hidden = false; expired(error); }
  }
  $('photo-close').addEventListener('click', () => $('photo-viewer').close());
  $('photo-viewer').addEventListener('click', event => { if (event.target === $('photo-viewer')) $('photo-viewer').close(); });
  $('photo-viewer').addEventListener('close', () => { document.body.classList.remove('viewing-photo'); $('photo-large').removeAttribute('src'); });
  $('photo-large').addEventListener('error', () => { if (!$('photo-viewer').open) return; $('photo-large').hidden = true; $('photo-error').hidden = false; });
  $('search').addEventListener('input', render);
  $('notes').addEventListener('input', save);
  $('retry').addEventListener('click', load);
  $('open-cart').addEventListener('click', () => {
    if (!$('review').hidden) return;
    catalogScroll = window.scrollY; save();
    history.pushState({ catalogToken: token, view: 'review' }, '', location.href);
    showView('review'); render();
  });
  $('back').addEventListener('click', () => history.back());
  $('confirm').addEventListener('click', async () => {
    if (sending) return;
    if (!pending) pending = { p_solicitud_id: crypto.randomUUID(), p_items: core.items(products, basket), p_observacion: $('notes').value.trim() };
    sending = true; save(); render(); message('Enviando pedido…');
    try {
      const result = await rpc('crear_pedido_catalogo', { p_token: token, ...pending });
      basket = {}; pending = null; $('notes').value = ''; save();
      history.replaceState({ catalogToken: token, view: 'success' }, '', location.href);
      showView('success');
      $('receipt').textContent = `Referencia: ${result.pedido_id} · Total: ${core.money(result.total)}`;
      message('');
    } catch (error) {
      if (!error.uncertain) { pending = null; save(); }
      message(error.message, true);
      if (!error.uncertain) $('retry').hidden = false;
      expired(error);
    } finally { sending = false; render(); }
  });
  $('new-order').addEventListener('click', () => { history.replaceState({ catalogToken: token, view: 'catalog' }, '', location.href); showView('catalog'); load(); });
  load();
})();
