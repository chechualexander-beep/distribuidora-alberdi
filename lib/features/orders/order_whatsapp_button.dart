import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/whatsapp_link.dart';

class OrderWhatsAppButton extends StatefulWidget {
  const OrderWhatsAppButton({
    super.key,
    required this.clientId,
    required this.message,
    this.client,
    this.launch = launchWhatsAppLink,
    this.compact = false,
    this.enabled = true,
  });

  final String? clientId;
  final String Function() message;
  final SupabaseClient? client;
  final WhatsAppLauncher launch;
  final bool compact;
  final bool enabled;

  @override
  State<OrderWhatsAppButton> createState() => _OrderWhatsAppButtonState();
}

class _OrderWhatsAppButtonState extends State<OrderWhatsAppButton> {
  bool _busy = false;
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;

  /// `otherNumber`: enviar a un número distinto del guardado (por ejemplo, el encargado),
  /// sin cambiar la ficha del cliente.
  Future<void> _open({bool otherNumber = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final actor = _client.auth.currentUser?.id;
      if (actor == null) {
        _notice('Iniciá sesión para consultar el teléfono del cliente.');
        return;
      }
      final clientId = widget.clientId!;
      final text = widget.message();
      final customer = await _client
          .from('clientes')
          .select('telefono,preventista_id')
          .eq('id', clientId)
          .maybeSingle();
      if (!mounted || _client.auth.currentUser?.id != actor) return;
      if (customer == null) {
        _notice(
          'No se encontró el cliente del pedido o no tenés acceso a su ficha.',
        );
        return;
      }
      final previous = customer['telefono'] as String?;
      var number = otherNumber ? null : normalizeArgentineWhatsApp(previous);
      if (number == null) {
        final canSave =
            !otherNumber && await _canEdit(actor, customer['preventista_id']);
        if (!mounted || _client.auth.currentUser?.id != actor) return;
        final choice = await showDialog<({String number, bool save})>(
          context: context,
          builder: (_) => _WhatsAppNumberDialog(
            previous: otherNumber ? null : previous,
            canSave: canSave,
            otherNumber: otherNumber,
          ),
        );
        if (choice == null ||
            !mounted ||
            _client.auth.currentUser?.id != actor) {
          return;
        }
        number = choice.number;
        if (choice.save) {
          try {
            var update = _client
                .from('clientes')
                .update({'telefono': '+$number'})
                .eq('id', clientId);
            update = previous == null
                ? update.isFilter('telefono', null)
                : update.eq('telefono', previous);
            // RLS and the existing customer trigger enforce the update.
            await update.select('id').single();
          } catch (_) {
            _notice(
              'No se pudo guardar el teléfono. Volvé a consultar la ficha o usá el número sin guardarlo.',
            );
            return;
          }
        }
      }
      if (!mounted || _client.auth.currentUser?.id != actor) return;
      await openWhatsApp(context, number, text: text, launch: widget.launch);
    } catch (_) {
      _notice('No se pudo consultar el teléfono del cliente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _canEdit(String actor, Object? owner) async {
    try {
      final profile = await _client
          .from('usuarios')
          .select('rol,activo')
          .eq('id', actor)
          .maybeSingle();
      return profile?['activo'] == true &&
          (profile?['rol'] == 'administrador' ||
              (profile?['rol'] == 'preventista' && owner == actor));
    } catch (_) {
      return false;
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available =
        widget.enabled && !_busy && (widget.clientId?.isNotEmpty ?? false);
    const label = 'Enviar por WhatsApp';
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: label,
            onPressed: available ? () => _open() : null,
            icon: const Icon(Icons.chat_outlined),
          ),
          IconButton(
            tooltip: 'Enviar por WhatsApp a otro número',
            onPressed: available ? () => _open(otherNumber: true) : null,
            icon: const Icon(Icons.phone_forwarded_outlined),
          ),
        ],
      );
    }
    // Wrap: en pantallas angostas "Otro número" baja de renglón en vez de desbordar.
    return Wrap(
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          onPressed: available ? () => _open() : null,
          child: const Text(label),
        ),
        TextButton(
          onPressed: available ? () => _open(otherNumber: true) : null,
          child: const Text('Otro número'),
        ),
      ],
    );
  }
}

class _WhatsAppNumberDialog extends StatefulWidget {
  const _WhatsAppNumberDialog({
    required this.previous,
    required this.canSave,
    this.otherNumber = false,
  });

  final String? previous;
  final bool canSave;
  final bool otherNumber;

  @override
  State<_WhatsAppNumberDialog> createState() => _WhatsAppNumberDialogState();
}

class _WhatsAppNumberDialogState extends State<_WhatsAppNumberDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.previous);

  String? get _normalized => normalizeArgentineWhatsApp(_number.text);

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _confirm({required bool save}) {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop((number: _normalized!, save: save));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.otherNumber
          ? 'Enviar a otro número'
          : 'Agregar número de WhatsApp',
    ),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _number,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Celular con código de área',
              hintText: '11 2345-6789',
              helperText: 'Alberdi agrega +54 9 si hace falta.',
              errorMaxLines: 3,
            ),
            validator: (_) => _normalized != null
                ? null
                : 'Ingresá el número completo, incluido el código de área.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: () => _confirm(save: false),
        child: const Text('Usar sin guardar'),
      ),
      if (widget.canSave)
        FilledButton(
          onPressed: () => _confirm(save: true),
          child: const Text('Guardar y abrir'),
        ),
    ],
  );
}
