import 'package:flutter/material.dart';
import 'stock_models.dart';
import 'stock_service.dart';

class StockAdjustDialog extends StatefulWidget {
  const StockAdjustDialog({
    super.key,
    required this.product,
    required this.location,
    required this.service,
  });
  final StockProduct product;
  final StockLocation location;
  final StockService service;
  @override
  State<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<StockAdjustDialog> {
  final _quantity = TextEditingController();
  final _other = TextEditingController();
  final _observation = TextEditingController();
  String _reason = 'Diferencia de inventario';
  bool _saving = false;
  String? _error;
  static const _reasons = [
    'Diferencia de inventario',
    'Rotura',
    'Vencimiento',
    'Faltante',
    'Error de carga',
    'Otro',
  ];
  @override
  void dispose() {
    _quantity.dispose();
    _other.dispose();
    _observation.dispose();
    super.dispose();
  }

  StockQuantity? get _newQuantity {
    try {
      return StockQuantity.input(_quantity.text);
    } on FormatException {
      return null;
    }
  }

  StockQuantity? get _delta =>
      _newQuantity?.difference(widget.product.quantity);
  String get _actualReason => _reason == 'Otro' ? _other.text.trim() : _reason;
  bool get _valid =>
      _delta != null &&
      _delta!.millis != 0 &&
      _actualReason.isNotEmpty &&
      _actualReason.length <= 200 &&
      _observation.text.length <= 2000;
  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.adjust(
        widget.location.id,
        widget.product.id,
        _newQuantity!,
        _actualReason,
        _observation.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = stockError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Ajustar stock'),
      content: SizedBox(
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.product.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Stock actual: ${widget.product.quantity.format()}'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('physical-count'),
              controller: _quantity,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Conteo físico',
                errorText: quantityError(_quantity.text),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('Diferencia: ${_delta?.format(signed: true) ?? '—'}'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Motivo'),
              items: [
                for (final reason in _reasons)
                  DropdownMenuItem(value: reason, child: Text(reason)),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _reason = value!),
            ),
            if (_reason == 'Otro')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _other,
                  enabled: !_saving,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Motivo obligatorio',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _observation,
              enabled: !_saving,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || !_valid ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}
