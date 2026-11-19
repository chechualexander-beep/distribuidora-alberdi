import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'finance_data.dart';

/// Lo que un formulario quiere enviar: función, parámetros y texto para "Pendientes de enviar".
class FinRequest {
  const FinRequest(this.rpc, this.args, this.description, [this.total = 0]);
  final String rpc;
  final Map<String, dynamic> args;
  final String description;
  final double total;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Widget moneyField(TextEditingController controller, String label, {bool autofocus = false, String? helper}) =>
    TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '\$ ',
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    );

Widget accountPicker(String value, ValueChanged<String> onChanged) => SegmentedButton<String>(
  segments: const [
    ButtonSegment(value: efectivo, label: Text('Efectivo'), icon: Icon(Icons.payments_outlined)),
    ButtonSegment(value: billetera, label: Text('Billetera'), icon: Icon(Icons.phone_android)),
  ],
  selected: {value},
  onSelectionChanged: (v) => onChanged(v.first),
);

Widget _error(String? text) => text == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, style: const TextStyle(color: AppColors.rojo)),
      );

Future<T?> _form<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, StateSetter set) body,
  required T? Function(StateSetter set) onSave,
  String saveLabel = 'Guardar',
}) => showDialog<T>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, set) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: body(context, set))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final result = onSave(set);
            if (result != null) Navigator.pop(context, result);
          },
          child: Text(saveLabel),
        ),
      ],
    ),
  ),
);

/// Gasto del negocio, plata para la casa, pase entre cuentas o ingreso extra.
Future<FinRequest?> showMovementForm(BuildContext context, {required String tipo}) {
  final amount = TextEditingController();
  final note = TextEditingController();
  var cuenta = efectivo;
  var destino = efectivo;
  String? categoria;
  String? error;
  final title = switch (tipo) {
    'gasto' => 'Anotar gasto',
    'hogar' => 'Dejé plata en casa',
    'pase' => 'Pase entre cuentas',
    _ => 'Ingreso extra',
  };
  if (tipo == 'pase') cuenta = billetera;
  return _form<FinRequest>(
    context,
    title: title,
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tipo == 'hogar')
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Lo que sale del negocio para la casa. No hace falta anotar en qué se gasta.'),
          ),
        moneyField(amount, 'Importe', autofocus: true),
        const SizedBox(height: 12),
        if (tipo == 'pase')
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: billetera, label: Text('Billetera → Efectivo')),
              ButtonSegment(value: efectivo, label: Text('Efectivo → Billetera')),
            ],
            selected: {cuenta},
            onSelectionChanged: (v) => set(() {
              cuenta = v.first;
              destino = cuenta == efectivo ? billetera : efectivo;
            }),
          )
        else ...[
          Text(tipo == 'ingreso' ? 'Entró en' : 'Salió de', style: const TextStyle(color: AppColors.gris)),
          const SizedBox(height: 4),
          accountPicker(cuenta, (v) => set(() => cuenta = v)),
        ],
        if (tipo == 'gasto') ...[
          const SizedBox(height: 12),
          const Text('¿En qué?', style: TextStyle(color: AppColors.gris)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in categoriasGasto)
                ChoiceChip(label: Text(c), selected: categoria == c, onSelected: (_) => set(() => categoria = c)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Detalle (opcional)', border: OutlineInputBorder()),
        ),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(amount.text);
      if (value == null || value <= 0) {
        set(() => error = 'Escribí el importe (mayor que 0).');
        return null;
      }
      if (tipo == 'gasto' && categoria == null) {
        set(() => error = 'Elegí en qué fue el gasto.');
        return null;
      }
      if (tipo == 'pase') destino = cuenta == efectivo ? billetera : efectivo;
      final detail = note.text.trim();
      return FinRequest(
        'fin_movimiento',
        {
          'p_tipo': tipo,
          'p_cuenta': cuenta,
          'p_importe': value,
          'p_categoria': categoria,
          'p_descripcion': detail.isEmpty ? null : detail,
          'p_cuenta_destino': tipo == 'pase' ? destino : null,
        },
        '$title${categoria == null ? '' : ' · $categoria'}',
        value,
      );
    },
  );
}

/// Alta o cambio de un gasto fijo. Devuelve los parámetros de fin_gasto_fijo_guardar (sin p_id).
Future<Map<String, dynamic>?> showFixedExpenseForm(BuildContext context, {FixedExpense? current}) {
  final name = TextEditingController(text: current?.nombre ?? '');
  final amount = TextEditingController(text: current == null ? '' : pesos(current.importe).replaceAll('\$ ', ''));
  final day = TextEditingController(text: current?.diaPago.toString() ?? '1');
  var ambito = current?.ambito ?? 'negocio';
  var activo = current?.activo ?? true;
  String? error;
  return _form<Map<String, dynamic>>(
    context,
    title: current == null ? 'Nuevo gasto fijo' : 'Gasto fijo',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Cuota del vehículo',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        moneyField(amount, 'Importe por mes', helper: 'Si cambia cada mes, poné el aproximado.'),
        const SizedBox(height: 12),
        TextField(
          controller: day,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Día de pago (1 a 31)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        const Text('¿De quién es?', style: TextStyle(color: AppColors.gris)),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'negocio', label: Text('Negocio')),
            ButtonSegment(value: 'hogar', label: Text('Hogar')),
            ButtonSegment(value: 'mixto', label: Text('Mixto')),
          ],
          selected: {ambito},
          onSelectionChanged: (v) => set(() => ambito = v.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            switch (ambito) {
              'hogar' => 'Se paga con plata del negocio pero es de la casa: cuenta como plata para el hogar.',
              'mixto' => 'Como la tarjeta: al pagarlo indicás cuánto fue para la casa.',
              _ => 'Gasto del negocio.',
            },
            style: const TextStyle(fontSize: 13, color: AppColors.gris),
          ),
        ),
        if (current != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            subtitle: const Text('Si lo apagás, deja de apartarse.'),
            value: activo,
            onChanged: (v) => set(() => activo = v),
          ),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(amount.text);
      final d = int.tryParse(day.text.trim());
      if (name.text.trim().isEmpty) {
        set(() => error = 'Escribí el nombre.');
        return null;
      }
      if (value == null || value <= 0) {
        set(() => error = 'Escribí el importe (mayor que 0).');
        return null;
      }
      if (d == null || d < 1 || d > 31) {
        set(() => error = 'El día de pago va del 1 al 31.');
        return null;
      }
      return {
        'p_nombre': name.text.trim(),
        'p_importe': value,
        'p_dia': d,
        'p_ambito': ambito,
        'p_activo': activo,
      };
    },
  );
}

/// Pagar el gasto fijo del período que vence.
Future<FinRequest?> showPayFixedForm(BuildContext context, FixedExpense expense) {
  final amount = TextEditingController(text: pesos(expense.importe).replaceAll('\$ ', ''));
  final home = TextEditingController();
  var cuenta = efectivo;
  String? error;
  return _form<FinRequest>(
    context,
    title: 'Pagar ${expense.nombre}',
    saveLabel: 'Pagado',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Vence el ${diaMes(expense.vence)}.', style: const TextStyle(color: AppColors.gris)),
        const SizedBox(height: 12),
        moneyField(amount, 'Lo que pagaste', helper: 'Cambialo si vino otro importe.'),
        if (expense.ambito == 'mixto') ...[
          const SizedBox(height: 12),
          moneyField(home, 'De eso, ¿cuánto fue de la casa?'),
        ],
        const SizedBox(height: 12),
        const Text('Lo pagaste con', style: TextStyle(color: AppColors.gris)),
        const SizedBox(height: 4),
        accountPicker(cuenta, (v) => set(() => cuenta = v)),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(amount.text);
      if (value == null || value <= 0) {
        set(() => error = 'Escribí lo que pagaste.');
        return null;
      }
      double? part;
      if (expense.ambito == 'mixto') {
        part = parseMoney(home.text);
        if (part == null || part > value) {
          set(() => error = 'Indicá cuánto fue de la casa (0 si nada, hasta el total).');
          return null;
        }
      }
      return FinRequest(
        'fin_pagar_gasto_fijo',
        {
          'p_gasto_fijo_id': expense.id,
          'p_periodo': isoDate(expense.vence),
          'p_cuenta': cuenta,
          'p_importe': value,
          'p_parte_hogar': part,
        },
        'Gasto fijo · ${expense.nombre}',
        value,
      );
    },
  );
}

/// Compra a pagar (proveedor con plazo).
Future<FinRequest?> showDebtForm(BuildContext context, {String? supplier, double? amount}) {
  final name = TextEditingController(text: supplier ?? '');
  final total = TextEditingController(text: amount == null ? '' : pesos(amount).replaceAll('\$ ', ''));
  final note = TextEditingController();
  var due = DateTime.now().add(const Duration(days: 15));
  String? error;
  return _form<FinRequest>(
    context,
    title: 'Proveedor a pagar',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Proveedor', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        moneyField(total, 'Importe'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text('Vence el ${diaMes(due)}'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: due,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 120)),
            );
            if (picked != null) set(() => due = picked);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Detalle (opcional)', border: OutlineInputBorder()),
        ),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(total.text);
      if (name.text.trim().isEmpty) {
        set(() => error = 'Escribí el proveedor.');
        return null;
      }
      if (value == null || value <= 0) {
        set(() => error = 'Escribí el importe (mayor que 0).');
        return null;
      }
      final detail = note.text.trim();
      return FinRequest(
        'fin_deuda',
        {
          'p_proveedor': name.text.trim(),
          'p_importe': value,
          'p_vence': isoDate(due),
          'p_descripcion': detail.isEmpty ? null : detail,
        },
        'A pagar · ${name.text.trim()}',
        value,
      );
    },
  );
}

Future<FinRequest?> showPayDebtForm(BuildContext context, Debt debt) {
  final amount = TextEditingController(text: pesos(debt.resta).replaceAll('\$ ', ''));
  var cuenta = efectivo;
  String? error;
  return _form<FinRequest>(
    context,
    title: 'Pagar a ${debt.proveedor}',
    saveLabel: 'Pagado',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Se debe ${pesos(debt.resta)} · vence el ${diaMes(debt.vence)}', style: const TextStyle(color: AppColors.gris)),
        const SizedBox(height: 12),
        moneyField(amount, 'Lo que pagás'),
        const SizedBox(height: 12),
        accountPicker(cuenta, (v) => set(() => cuenta = v)),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(amount.text);
      if (value == null || value <= 0 || value > debt.resta + 0.001) {
        set(() => error = 'Entre \$ 1 y ${pesos(debt.resta)}.');
        return null;
      }
      return FinRequest(
        'fin_pagar_deuda',
        {'p_deuda_id': debt.id, 'p_cuenta': cuenta, 'p_importe': value},
        'Pago a ${debt.proveedor}',
        value,
      );
    },
  );
}

/// Arqueo: contar el efectivo (o mirar la billetera) y comparar.
Future<FinRequest?> showCountForm(BuildContext context, FinState state) {
  final amount = TextEditingController();
  var cuenta = efectivo;
  String? error;
  return _form<FinRequest>(
    context,
    title: 'Arqueo',
    saveLabel: 'Comparar',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountPicker(cuenta, (v) => set(() => cuenta = v)),
        const SizedBox(height: 8),
        Text(
          'Según la app hay ${pesos(state.saldo(cuenta))}.',
          style: const TextStyle(color: AppColors.gris),
        ),
        const SizedBox(height: 12),
        moneyField(
          amount,
          cuenta == efectivo ? '¿Cuánto efectivo contaste?' : '¿Cuánto dice la billetera?',
          autofocus: true,
        ),
        const SizedBox(height: 8),
        const Text(
          'La diferencia queda anotada como sobrante o faltante y el saldo pasa a ser lo que contaste.',
          style: TextStyle(fontSize: 13, color: AppColors.gris),
        ),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(amount.text);
      if (value == null) {
        set(() => error = 'Escribí cuánto hay (0 si no hay nada).');
        return null;
      }
      return FinRequest(
        'fin_arqueo',
        {'p_cuenta': cuenta, 'p_contado': value},
        'Arqueo · ${cuentaNombre(cuenta)}',
        value,
      );
    },
  );
}
