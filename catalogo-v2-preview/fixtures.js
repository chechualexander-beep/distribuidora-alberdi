(() => {
  'use strict';
  const products = [
    ['P01','Yerba mate suave','Paquete de 1 kg','Almacén',3290,'yerba',true],
    ['P02','Galletitas de avena','Paquete de 240 g','Desayuno',1450,'galletas',true],
    ['P03','Aceite de girasol','Botella de 900 ml','Almacén',2950,'aceite',true],
    ['P04','Jugo de naranja','Botella de 1 L','Bebidas',1380,'jugo',true],
    ['P05','Arroz largo fino','Paquete de 1 kg','Almacén',1720,'arroz',false,true],
    ['P06','Café molido','Paquete de 250 g','Desayuno',4830,'cafe',false,true],
    ['P07','Papas clásicas','Bolsa de 150 g','Snacks',1830,'papas',false,true],
    ['P08','Pasta seca tirabuzón','Paquete de 500 g','Almacén',1215],
    ['P09','Agua sin gas','Botella de 2 L','Bebidas',840],
    ['P10','Jabón para ropa','Botella de 1 L','Limpieza',2870],
    ['P11','Lentejas secas','Paquete de 500 g','Almacén',1960],
    ['P12','Tostadas integrales','Paquete de 200 g','Desayuno',1475],
    ['P13','Maní tostado','Bolsa de 120 g','Snacks',1220],
    ['P14','Detergente limón','Botella de 750 ml','Limpieza',1580],
  ].map(([codigo,nombre,descripcion,categoria,precio,image,promocion=false,destacado=false]) => ({
    id: codigo, codigo, nombre, descripcion, categoria, precio,
    miniatura: image ? 'img/' + image + '.svg' : null, promocion, destacado,
  }));
  globalThis.CatalogoPreviewFixture = { nombre_comercio: 'Almacén de muestra', productos: products };
})();
