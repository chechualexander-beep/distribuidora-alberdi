import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new OS process recovers invoice UUID and rejects changed preparation implicitly',
    () async {
      final output = p.join(
        Directory.current.path,
        '.dart_tool',
        'invoice_probe',
      );
      final build = await Process.run(
        r'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe',
        [
          'build',
          'cli',
          '-t',
          'test/helpers/invoice_process_probe.dart',
          '-o',
          output,
        ],
        environment: {
          'PUB_CACHE': r'C:\AlberdiTesting\dependencies\pub-cache',
          'DART_SUPPRESS_ANALYTICS': 'true',
        },
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      final base = await Directory(
        p.join(Directory.current.path, '.dart_tool', 'invoice_fixtures'),
      ).create(recursive: true);
      final dir = await base.createTemp('restart-');
      addTearDown(() => dir.delete(recursive: true));
      Future<Map<String, dynamic>> worker(String mode) async {
        final r = await Process.run(
          p.join(output, 'bundle', 'bin', 'invoice_process_probe.exe'),
          [dir.path, mode],
        );
        expect(r.exitCode, 0, reason: '${r.stderr}');
        return Map<String, dynamic>.from(jsonDecode(r.stdout as String) as Map);
      }

      final first = await worker('create');
      expect(await worker('read'), first);
      expect(await worker('changed'), first);
      expect(first['p_originales'][0]['cantidad_facturada'], 1);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
