(() => {
  'use strict';

  const $ = id => document.getElementById(id);
  const core = globalThis.CatalogoCore;
  const fixture = globalThis.CatalogoPreviewFixture;
  const options = new URLSearchParams(location.search);
  const personalized = options.get('modo') !== 'general';
  const noShelves = options.has('sin-bloques');
  const products = fixture.productos;
  const byId = new Map(products.map(product => [product.id, product]));
  const storageKey = 'alberdi:v2:preview:cart';
  const instances = { promo: new Map(), featured: new Map(), list: new Map(), cart: new Map() };
  let category = '';
  let basket = {};
  let scroll = 0;
  let view = 'catalog';
  let receipt = null;

  if (personalized) {
    try {
      const saved = JSON.parse(sessionStorage.getItem(storageKey) || '{}');
      basket = core.reconcile(products, saved.basket || {});
      $('notes').value = typeof saved.notes === 'string' ? saved.notes : '';
    } catch { /* El carrito también funciona sin almacenamiento. */ }
  }

  function save() {
    try {
      sessionStorage.setItem(storageKey, JSON.stringify({ basket, notes: $('notes').value }));
    } catch { /* Almacenamiento opcional. */ }
  }

  function element(tag, className, value) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (value !== undefined) node.textContent = value;
    return node;
  }

  function thumbnail(product) {
    const holder = element('div', 'thumb');
    const placeholder = () => holder.replaceChildren(element('span', '', 'Sin foto'));
    if (!/^img\/[a-z]+\.svg$/.test(product.miniatura || '')) {
      placeholder();
    } else {
      const img = element('img');
      img.alt = '';
      img.loading = 'lazy';
      img.decoding = 'async';
      img.addEventListener('error', placeholder, { once: true });
      img.src = product.miniatura;
      holder.append(img);
    }
    return holder;
  }

  function quantity(product, surface) {
    const node = $('quantity-template').content.firstElementChild.cloneNode(true);
    const minus = node.querySelector('.minus');
    const plus = node.querySelector('.plus');
    const count = node.querySelector('output');
    minus.setAttribute('aria-label', 'Quitar una unidad de ' + product.nombre);
    plus.setAttribute('aria-label', 'Agregar una unidad de ' + product.nombre);
    count.setAttribute('aria-label', 'Cantidad de ' + product.nombre);
    minus.addEventListener('click', () => change(product.id, -1));
    plus.addEventListener('click', () => change(product.id, 1));
    instances[surface].set(product.id, { minus, plus, count });
    updateProduct(product.id);
    return node;
  }

  function updateProduct(id) {
    const amount = basket[id] || 0;
    for (const surface of Object.values(instances)) {
      const controls = surface.get(id);
      if (controls) {
        controls.count.value = String(amount);
        controls.minus.disabled = amount === 0;
        controls.plus.disabled = amount >= 9999;
      }
    }
  }

  function change(id, step) {
    const amount = Math.min(9999, Math.max(0, (basket[id] || 0) + step));
    if (amount) basket[id] = amount;
    else delete basket[id];
    updateProduct(id);
    if (view === 'review' && amount === 0) renderCart();
    updateTotals();
    save();
  }

  function productCard(product, surface) {
    const style = surface === 'promo' ? 'promo' : surface === 'featured' ? 'highlight' : 'product';
    const row = element('article', style);
    row.dataset.product = product.id;
    const details = element('div');
    details.append(element('h3', '', product.nombre));
    if (style === 'product') details.append(element('p', 'muted', product.descripcion));
    if (Number.isFinite(product.precio)) details.append(element('p', 'price', core.money(product.precio)));
    row.append(thumbnail(product), details);
    if (surface === 'promo') row.append(element('span', 'badge', 'Promoción'));
    if (personalized && Number.isFinite(product.precio)) row.append(quantity(product, surface));
    return row;
  }

  function shelf(section, rail, surface, flag) {
    const items = noShelves ? [] : products.filter(p => p[flag] === true);
    $(section).hidden = items.length === 0;
    $(rail).replaceChildren(...items.map(product => productCard(product, surface)));
  }

  function renderList() {
    instances.list.clear();
    const search = $('search').value;
    $('showcase').hidden = search.trim().length > 0;
    const visible = core.filter(products, search, category);
    $('products').replaceChildren(...visible.map(product => productCard(product, 'list')));
    $('count').textContent = visible.length
      ? visible.length + (visible.length === 1 ? ' producto' : ' productos')
      : 'Sin resultados';
    for (const button of $('categories').children) {
      button.setAttribute('aria-pressed', String(button.dataset.category === category));
    }
  }

  function renderCart() {
    instances.cart.clear();
    const selected = products.filter(product => basket[product.id] > 0);
    $('cart-items').replaceChildren(...(selected.length
      ? selected.map(product => productCard(product, 'cart'))
      : [element('p', 'muted', 'Tu pedido está vacío.')]));
  }

  function totals() {
    let units = 0;
    let cents = 0;
    for (const [id, amount] of Object.entries(basket)) {
      units += amount;
      cents += Math.round(byId.get(id).precio * 100) * amount;
    }
    return { units, total: cents / 100 };
  }

  function updateTotals() {
    const { units, total } = totals();
    $('cart-count').textContent = units ? 'Ver mi pedido · ' + units : 'Ver mi pedido';
    $('cart-total').textContent = core.money(total);
    $('review-total').textContent = 'Total: ' + core.money(total);
    $('open-cart').disabled = units === 0;
    $('confirm').disabled = units === 0;
  }

  function show(next) {
    view = next;
    for (const name of ['catalog', 'review', 'success']) $(name).hidden = name !== next;
    $('cart-bar').hidden = next !== 'catalog' || !personalized;
    if (next === 'review') renderCart();
    updateTotals();
    window.scrollTo(0, next === 'catalog' ? scroll : 0);
    if (next !== 'catalog') $(next + '-title').focus({ preventScroll: true });
  }

  $('greeting').textContent = personalized ? 'Hola, ' + fixture.nombre_comercio : 'Catálogo general';
  $('validity').textContent = personalized
    ? 'Enlace de demostración · vigencia simulada de 12 horas'
    : 'Vidriera de demostración · productos y precios ficticios';
  shelf('promotions', 'promo-rail', 'promo', 'promocion');
  shelf('featured', 'featured-rail', 'featured', 'destacado');
  for (const value of ['', ...new Set(products.map(p => p.categoria))]) {
    const button = element('button', '', value || 'Todos');
    button.type = 'button';
    button.dataset.category = value;
    button.addEventListener('click', () => { category = value; renderList(); });
    $('categories').append(button);
  }
  $('search').addEventListener('input', renderList);
  $('notes').addEventListener('input', save);
  $('open-cart').addEventListener('click', () => {
    scroll = window.scrollY;
    history.pushState({ previewView: 'review' }, '');
    show('review');
  });
  $('back').addEventListener('click', () => history.back());
  $('confirm').addEventListener('click', () => {
    const items = core.items(products, basket);
    if (view !== 'review' || !items.length) return;
    receipt = { id: crypto.randomUUID(), items, total: totals().total };
    basket = {};
    $('notes').value = '';
    save();
    for (const product of products) updateProduct(product.id);
    $('receipt').textContent = 'Referencia local: ' + receipt.id.slice(0, 8) + ' · ' + core.money(receipt.total);
    history.replaceState({ previewView: 'success' }, '');
    show('success');
  });
  $('new-order').addEventListener('click', () => history.back());
  history.scrollRestoration = 'manual';
  window.addEventListener('popstate', event => {
    const next = event.state?.previewView;
    show(next === 'review' && personalized ? 'review' : next === 'success' && receipt ? 'success' : 'catalog');
    if (view === 'catalog' && personalized) $('open-cart').focus({ preventScroll: true });
  });
  history.replaceState({ previewView: 'catalog' }, '');
  renderList();
  show('catalog');
})();
