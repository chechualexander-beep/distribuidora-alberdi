import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'invoice_request.dart';
import 'invoice_snapshot_pdf.dart';
import '../../core/local_outbox.dart';

class InvoiceRecoveryPage extends StatefulWidget {
  const InvoiceRecoveryPage({super.key});
  @override
  State<InvoiceRecoveryPage> createState() => _InvoiceRecoveryPageState();
}

class _InvoiceRecoveryPageState extends State<InvoiceRecoveryPage> {
  InvoiceService? _service;
  String? _error;
  bool _busy = false;
  OutboxRecord? _safeRecord(InvoiceService service, String id) {
    try {
      return service.store.read(id);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = await invoiceService(Supabase.instance.client);
      service.store.pending; // Fails closed on corrupt records.
      if (mounted) {
        setState(() {
          _service = service;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo abrir la cola de boletas. Se conserva para revisión.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La boleta se conserva. Revisá su estado; no crees otra solicitud.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    List<String> ids;
    try {
      ids = s?.store.pending ?? <String>[];
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recuperación de boletas internas')),
        body: const Center(
          child: Text(
            'El almacén no se puede leer. Se conserva para revisión; no se habilita otra emisión.',
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperación de boletas internas')),
      body: _error != null
          ? Center(child: Text(_error!))
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : ids.isEmpty
          ? const Center(
              child: Text(
                'No hay boletas pendientes de confirmación o impresión.',
              ),
            )
          : ListView(
              children: [
                for (final id in ids)
                  Builder(
                    builder: (context) {
                      final saved = _safeRecord(s, id);
                      if (saved == null) {
                        return const Card(
                          child: Text(
                            'Solicitud dañada: requiere revisión, sin reenvío.',
                          ),
                        );
                      }
                      final confirmed = saved.result != null;
                      final review = saved.state == 'review';
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pedido: $id'),
                              Text(
                                'Solicitud: ${saved.payload['p_solicitud_id']}',
                              ),
                              Text(
                                review
                                    ? 'Error o conflicto: requiere revisión'
                                    : confirmed
                                    ? 'Boleta confirmada — impresión pendiente'
                                    : 'Boleta pendiente de confirmación',
                              ),
                              if (!review && !confirmed)
                                Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(() async {
                                              await s.reconcile(id);
                                            }),
                                      child: const Text(
                                        'Consultar confirmación',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _busy || !s.enabled
                                          ? null
                                          : () => _run(() async {
                                              await s.reconcile(
                                                id,
                                                sendIfAbsent: true,
                                              );
                                            }),
                                      child: const Text(
                                        'Reintentar solicitud original',
                                      ),
                                    ),
                                  ],
                                ),
                              if (confirmed)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                          await s.printConfirmed(
                                            id,
                                            (doc) async => Printing.layoutPdf(
                                              onLayout: (_) =>
                                                  InvoiceSnapshotPdf.generate(
                                                    doc,
                                                  ),
                                              name: 'Boleta_${doc.number}',
                                              format: PdfPageFormat.a5,
                                            ),
                                          );
                                        }),
                                  child: const Text(
                                    'Visualizar / imprimir boleta confirmada',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
