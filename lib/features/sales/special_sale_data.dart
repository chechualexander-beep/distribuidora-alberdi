import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money_format.dart';
import '../stock/stock_data.dart';

/// Cliente fijo para ventas a quien no está cargado (se cobra siempre en el momento).
const consumidorFinalId = 'c0f1a1a1-0000-4000-8000-000000000001';

class SaleClient {
  const SaleClient(this.id, this.name, [this.priceList]);
  final String id;
  final String name;

  /// normal, promo o interior (precio de lista con que arranca cada producto).
  final String? priceList;
  bool get isFinalConsumer => id == consumidorFinalId;
  static const finalConsumer = SaleClient(consumidorFinalId, 'Consumidor final');
}

class SaleProduct {
  const SaleProduct({
    required this.id,
    required this.name,
    required this.code,
    required this.cost,
    required this.controlled,
    required this.deposit,
    required this.vehicle,
    required this.normal,
    this.promo,
    this.interior,
  });

  final String id;
  final String name;
  final String code;
  final double cost;
  final bool controlled;
  final double deposit;
  final double vehicle;
  final double normal;
  final double? promo;
  final double? interior;

  double priceFor(String? list) => switch (list) {
    'promo' when (promo ?? 0) > 0 => promo!,
    'interior' when (interior ?? 0) > 0 => interior!,
    _ => normal,
  };

  double stockAt(String location) => location == vehiculoCodigo ? vehicle : deposit;
}

/// Una línea de la venta: precio a mano (arranca con el de lista).
class SaleLine {
  SaleLine(this.product, {this.quantity = 1, required this.price});
  final SaleProduct product;
  double quantity;
  double price;

  double get total => (quantity * price * 100).round() / 100;
  double get cost => quantity * product.cost;
  double get profit => total - cost;

  /// Margen sobre el precio (null si no hay precio).
  double? get margin => price > 0 ? (price - product.cost) / price : null;
  bool get belowCost => product.cost > 0 && price < product.cost;
}

double saleTotal(List<SaleLine> lines) => lines.fold(0, (s, l) => s + l.total);
double saleCost(List<SaleLine> lines) => lines.fold(0, (s, l) => s + l.cost);

Future<List<SaleProduct>> fetchSaleProducts(SupabaseClient client) async {
  final items = await fetchStockItems(client);
  final rows = List<Map<String, dynamic>>.from(
    await client
        .from('productos_administracion')
        .select('id,precio_normal,precio_promo,precio_interior')
        .eq('activo', true),
  );
  final prices = {for (final r in rows) r['id'].toString(): r};
  return [
    for (final i in items)
      SaleProduct(
        id: i.id,
        name: i.name,
        code: i.code,
        cost: i.cost,
        controlled: i.controlled,
        deposit: i.deposit,
        vehicle: i.vehicle,
        normal: stockNum(prices[i.id]?['precio_normal']),
        promo: prices[i.id]?['precio_promo'] == null ? null : stockNum(prices[i.id]!['precio_promo']),
        interior: prices[i.id]?['precio_interior'] == null ? null : stockNum(prices[i.id]!['precio_interior']),
      ),
  ];
}

Future<List<SaleClient>> fetchSaleClients(SupabaseClient client) async {
  final rows = List<Map<String, dynamic>>.from(
    await client.from('clientes').select('id,nombre_comercio,tipo_precio_habitual').eq('activo', true).order('nombre_comercio'),
  );
  return [
    for (final r in rows)
      if (r['id'].toString() != consumidorFinalId)
        SaleClient(r['id'].toString(), r['nombre_comercio']?.toString() ?? 'Cliente', r['tipo_precio_habitual']?.toString()),
  ];
}

/// Texto para mandar por WhatsApp.
String saleMessage({
  required List<SaleLine> lines,
  required Map<String, double> payments,
  DateTime? when,
}) {
  final d = when ?? DateTime.now();
  final date = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  final total = saleTotal(lines);
  final paid = payments.values.fold<double>(0, (s, v) => s + v);
  final b = StringBuffer('Distribuidora Alberdi\nVenta del $date\n\n');
  for (final l in lines) {
    b.writeln('${formatQty(l.quantity)} × ${l.product.name} — ${formatoPesos(l.price)} c/u = ${formatoPesos(l.total)}');
  }
  b.writeln('\nTotal: ${formatoPesos(total)}');
  if (paid > 0) {
    final detail = [for (final e in payments.entries) if (e.value > 0) '${e.key.toLowerCase()} ${formatoPesos(e.value)}'];
    b.writeln('Pagado: ${formatoPesos(paid)} (${detail.join(', ')})');
  }
  if (total - paid > 0.005) b.writeln('Saldo: ${formatoPesos(total - paid)}');
  b.write('\n¡Gracias por tu compra!');
  return b.toString();
}
