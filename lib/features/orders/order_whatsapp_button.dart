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

  Future<void> _open() async {
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
      var number = normalizeArgentineWhatsApp(previous);
      if (number == null) {
        final canSave = await _canEdit(actor, customer['preventista_id']);
        if (!mounted || _client.auth.currentUser?.id != actor) return;
        final choice = await showDialog<({String number, bool save})>(
          context: context,
          builder: (_) =>
              _WhatsAppNumberDialog(previous: previous, canSave: canSave),
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
      return IconButton(
        tooltip: label,
        onPressed: available ? _open : null,
        icon: const Icon(Icons.chat_outlined),
      );
    }
    return TextButton(
      onPressed: available ? _open : null,
      child: const Text(label),
    );
  }
}

class _WhatsAppNumberDialog extends StatefulWidget {
  const _WhatsAppNumberDialog({required this.previous, required this.canSave});

  final String? previous;
  final bool canSave;

  @override
  State<_WhatsAppNumberDialog> createState() => _WhatsAppNumberDialogState();
}

class _WhatsAppNumberDialogState extends State<_WhatsAppNumberDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.previous);
  bool _confirmedMobile = false;

  bool get _needsMobileConfirmation =>
      normalizeArgentineWhatsApp(_number.text) == null &&
      normalizeArgentineWhatsApp(_number.text, nationalMobileConfirmed: true) !=
          null;

  String? get _normalized => normalizeArgentineWhatsApp(
    _number.text,
    nationalMobileConfirmed: _confirmedMobile,
  );

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
    title: const Text('Agregar número de WhatsApp'),
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
            onChanged: (_) => setState(() => _confirmedMobile = false),
            validator: (_) {
              if (_normalized != null) return null;
              return _needsMobileConfirmation
                  ? 'Confirmá que el número es de un celular.'
                  : 'Ingresá el número completo, incluido el código de área.';
            },
          ),
          if (_needsMobileConfirmation)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Es un número de celular'),
              value: _confirmedMobile,
              onChanged: (value) => setState(() => _confirmedMobile = value!),
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
