import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:distribuidora_alberdi/core/local_outbox.dart';

Future<void> main(List<String> args) async {
  final nativeProbe = sqlite3.openInMemory();
  nativeProbe.close();
  final root = args[0], mode = args[1], worker = args[2];
  final db = await LocalOutbox.open(
    root,
    testingFault: (stage) {
      if (mode == 'crash_$stage') {
        File('$root/interrupted-$worker').writeAsString(stage, flush: true);
        exit(stage == 'before_commit' ? 71 : 72);
      }
    },
  );
  const key = OutboxKey('fake-local-scope', 'fake-actor', 'fake-order');
  if (mode == 'prepare' || mode.startsWith('crash_')) {
    await File('$root/started-$worker').writeAsString('ready', flush: true);
    final value = await db.prepare(key, (uuid) async {
      await File('$root/builder-$worker').writeAsString('entered', flush: true);
      if (worker == 'A') {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!await File('$root/release-A').exists()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Fixture gate timeout');
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
      return {
        'p_pedido_id': key.order,
        'p_solicitud_id': uuid,
        'p_fecha_fisica': '2026-01-01T00:00:00.000Z',
        'p_importe_pago': worker == 'B' ? 999 : 200,
      };
    });
    await File(
      '$root/result-$worker.json',
    ).writeAsString(jsonEncode(value), flush: true);
  } else if (mode == 'read') {
    await File(
      '$root/result-$worker.json',
    ).writeAsString(jsonEncode(db.read(key)?.payload), flush: true);
  } else if (mode == 'hold') {
    await db.withKeyLock(key, () async {
      await File('$root/locked-$worker').writeAsString('locked', flush: true);
      await Future<void>.delayed(const Duration(minutes: 2));
    });
  }
  db.close();
}
