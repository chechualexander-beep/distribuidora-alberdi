(function (host) {
  'use strict';
  const normalize = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
  const money = value => new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS' }).format(value);
  function filter(products, query, category) {
    const words = normalize(query).split(/\s+/).filter(Boolean);
    return products.filter(p => (!category || p.categoria === category) && words.every(w => normalize(`${p.nombre} ${p.codigo || ''} ${p.descripcion || ''}`).includes(w)));
  }
  function reconcile(products, basket) {
    const result = {};
    for (const p of products) {
      const n = Number(basket[p.id]);
      if (Number.isInteger(n) && n > 0 && n <= 9999) result[p.id] = n;
    }
    return result;
  }
  function items(products, basket) {
    return products.filter(p => basket[p.id] > 0).map(p => ({ producto_id: p.id, cantidad: basket[p.id], precio_visto: p.precio }));
  }
  const api = { normalize, money, filter, reconcile, items };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else host.CatalogoCore = api;
})(globalThis);
