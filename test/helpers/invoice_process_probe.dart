import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:distribuidora_alberdi/core/local_outbox.dart';

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0]));
  final allowed = p.join(
    Directory.current.path,
    '.dart_tool',
    'invoice_fixtures',
  );
  if (!p.isWithin(allowed, root)) {
    throw StateError('Only synthetic process fixtures allowed');
  }
  final db = await LocalOutbox.open(root);
  try {
    const key = OutboxKey(
      'boletas_v1:local',
      'fictional-admin',
      'fictional-order',
    );
    if (args[1] != 'read') {
      await db.prepare(
        key,
        (id) async => {
          'p_solicitud_id': id,
          'p_pedido_id': key.order,
          'p_regimen_id': '11111111-1111-4111-8111-111111111111',
          'p_originales': [
            {
              'detalle_id': 'fictional-detail',
              'cantidad_facturada': args[1] == 'create' ? 1 : 999,
            },
          ],
          'p_agregados': [],
        },
      );
    }
    stdout.writeln(jsonEncode(db.read(key)!.payload));
  } finally {
    db.close();
  }
}
