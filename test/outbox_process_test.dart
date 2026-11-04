import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> waitFile(String path) async {
  final deadline = DateTime.now().add(const Duration(seconds: 50));
  while (!await File(path).exists()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Fixture timeout: $path');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<Process> worker(String root, String mode, String name) async {
  final process = await Process.start(
    p.join(
      Directory.current.path,
      '.dart_tool',
      'outbox_probe',
      'bundle',
      'bin',
      'outbox_process_probe.exe',
    ),
    [root, mode, name],
    workingDirectory: Directory.current.path,
  );
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdout.drain<void>();
  addTearDown(() async {
    process.kill();
    await process.exitCode;
  });
  process.exitCode.then((code) async {
    if (code != 0 && name != 'D' && !mode.startsWith('crash_')) {
      fail('Fixture worker $name exit=$code ${await errors}');
    }
  });
  return process;
}

void main() {
  setUpAll(() async {
    final output = Directory(
      p.join(Directory.current.path, '.dart_tool', 'outbox_probe'),
    );
    await output.create(recursive: true);
    final compilation = await Process.run(
      r'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe',
      [
        '--suppress-analytics',
        'build',
        'cli',
        '-t',
        'tool/outbox_process_probe.dart',
        '-o',
        output.path,
      ],
      environment: {
        'PUB_CACHE': r'C:\AlberdiTesting\dependencies\pub-cache',
        'DART_SUPPRESS_ANALYTICS': 'true',
      },
    );
    expect(
      compilation.exitCode,
      0,
      reason: '${compilation.stdout}\n${compilation.stderr}',
    );
  });
  test(
    'distinct processes serialize preparations; new process recovers unchanged request',
    () async {
      final base = Directory(
        p.join(Directory.current.path, '.dart_tool', 'outbox_fixtures'),
      );
      await base.create(recursive: true);
      final dir = await base.createTemp('process-');
      final root = dir.path;
      final a = await worker(root, 'prepare', 'A');
      await waitFile('$root/builder-A');
      final b = await worker(root, 'prepare', 'B');
      await waitFile('$root/started-B');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await File('$root/builder-B').exists(), isFalse);
      await File('$root/release-A').writeAsString('go', flush: true);
      expect(await a.exitCode, 0);
      expect(await b.exitCode, 0);
      final original = jsonDecode(
        await File('$root/result-A.json').readAsString(),
      );
      expect(
        jsonDecode(await File('$root/result-B.json').readAsString()),
        original,
      );
      expect(original['p_importe_pago'], 200);
      final reader = await worker(root, 'read', 'C');
      expect(await reader.exitCode, 0);
      expect(
        jsonDecode(await File('$root/result-C.json').readAsString()),
        original,
      );
      final holder = await worker(root, 'hold', 'D');
      await waitFile('$root/locked-D');
      holder.kill();
      await holder.exitCode;
      final recovered = await worker(root, 'prepare', 'E');
      expect(await recovered.exitCode, 0);
      expect(
        jsonDecode(await File('$root/result-E.json').readAsString()),
        original,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  for (final stage in ['before_commit', 'after_commit']) {
    test('fresh process recovers after helper exits $stage', () async {
      final base = Directory(
        p.join(Directory.current.path, '.dart_tool', 'outbox_fixtures'),
      );
      await base.create(recursive: true);
      final dir = await base.createTemp('crash-');
      final interrupted = await worker(dir.path, 'crash_$stage', 'F');
      expect(await interrupted.exitCode, stage == 'before_commit' ? 71 : 72);
      final reader = await worker(dir.path, 'read', 'G');
      expect(await reader.exitCode, 0);
      final saved = jsonDecode(
        await File('${dir.path}/result-G.json').readAsString(),
      );
      if (stage == 'before_commit') {
        expect(saved, isNull);
      } else {
        expect(saved['p_importe_pago'], 200);
        expect(saved['p_fecha_fisica'], '2026-01-01T00:00:00.000Z');
        expect(saved['p_solicitud_id'], isNotEmpty);
      }
    });
  }
}
