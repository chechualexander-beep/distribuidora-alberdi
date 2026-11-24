import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/money_format.dart';
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
      inputFormatters: const [ImporteInputFormatter()],
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

/// "¿De quién es?": negocio, casa o personal. Lo de casa y personal no baja la ganancia del negocio.
Widget ownerPicker(String value, ValueChanged<String> onChanged, {bool negocio = true}) => SegmentedButton<String>(
  key: const Key('de-quien'),
  segments: [
    if (negocio) const ButtonSegment(value: 'negocio', label: Text('Negocio'), icon: Icon(Icons.storefront_outlined)),
    const ButtonSegment(value: 'casa', label: Text('Casa'), icon: Icon(Icons.home_outlined)),
    const ButtonSegment(value: 'personal', label: Text('Personal'), icon: Icon(Icons.person_outline)),
  ],
  selected: {value},
  onSelectionChanged: (v) => onChanged(v.first),
);

String ownerHelp(String owner) => switch (owner) {
  'casa' => 'Gasto de la casa pagado con plata del negocio: cuenta como retiro, no baja la ganancia.',
  'personal' => 'Gasto tuyo pagado con plata del negocio: cuenta como retiro, no baja la ganancia.',
  _ => 'Gasto del negocio: baja la ganancia.',
};

/// Gasto (del negocio, de la casa o personal), retiro, pase entre cuentas, ingreso extra o aporte del dueño.
Future<FinRequest?> showMovementForm(BuildContext context, {required String tipo}) {
  final amount = TextEditingController();
  final note = TextEditingController();
  var cuenta = efectivo;
  var destino = efectivo;
  var owner = tipo == 'hogar' ? 'casa' : 'negocio';
  var aporte = false;
  String? categoria;
  String? error;
  final title = switch (tipo) {
    'gasto' => 'Anotar gasto',
    'hogar' => 'Retiro para la casa o personal',
    'pase' => 'Pase entre cuentas',
    _ => 'Ingreso o aporte',
  };
  if (tipo == 'pase') cuenta = billetera;
  const gray = TextStyle(color: AppColors.gris);
  const small = TextStyle(fontSize: 13, color: AppColors.gris);
  return _form<FinRequest>(
    context,
    title: title,
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tipo == 'gasto' || tipo == 'hogar') ...[
          Text('¿De quién es?', style: gray),
          const SizedBox(height: 4),
          ownerPicker(owner, (v) => set(() => owner = v), negocio: tipo == 'gasto'),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Text(
              tipo == 'hogar'
                  ? 'Plata que sacás del negocio para la casa o para vos. No hace falta anotar en qué se gasta.'
                  : ownerHelp(owner),
              style: small,
            ),
          ),
        ],
        if (tipo == 'ingreso') ...[
          SegmentedButton<bool>(
            key: const Key('tipo-ingreso'),
            segments: const [
              ButtonSegment(value: false, label: Text('Ingreso extra')),
              ButtonSegment(value: true, label: Text('Aporte mío')),
            ],
            selected: {aporte},
            onSelectionChanged: (v) => set(() => aporte = v.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Text(
              aporte
                  ? 'Plata tuya (de afuera) que ponés en el negocio. Suma a la caja pero no es ganancia.'
                  : 'Plata que entra al negocio y no es un cobro a clientes.',
              style: small,
            ),
          ),
        ],
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
          Text(tipo == 'ingreso' ? 'Entró en' : 'Salió de', style: gray),
          const SizedBox(height: 4),
          accountPicker(cuenta, (v) => set(() => cuenta = v)),
        ],
        if (tipo == 'gasto' && owner == 'negocio') ...[
          const SizedBox(height: 12),
          Text('¿En qué?', style: gray),
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
      final retiro = tipo == 'hogar' || (tipo == 'gasto' && owner != 'negocio');
      if (tipo == 'gasto' && !retiro && categoria == null) {
        set(() => error = 'Elegí en qué fue el gasto.');
        return null;
      }
      if (tipo == 'pase') destino = cuenta == efectivo ? billetera : efectivo;
      final detail = note.text.trim();
      final cat = retiro
          ? (owner == 'personal' ? 'Personal' : 'Casa')
          : tipo == 'ingreso' && aporte
          ? aporteDelDueno
          : categoria;
      return FinRequest(
        'fin_movimiento',
        {
          'p_tipo': retiro ? 'hogar' : tipo,
          'p_cuenta': cuenta,
          'p_importe': value,
          'p_categoria': cat,
          'p_descripcion': detail.isEmpty ? null : detail,
          'p_cuenta_destino': tipo == 'pase' ? destino : null,
        },
        '$title${cat == null ? '' : ' · $cat'}',
        value,
      );
    },
  );
}

/// Fijar, cambiar o quitar el sueldo semanal. Devuelve el importe (null = quitarlo); cancelar → no cambia nada.
Future<({double? importe})?> showSalaryForm(BuildContext context, {double? current, double? suggested}) {
  final amount = TextEditingController(text: current == null ? '' : importeEditable(current));
  String? error;
  return _form<({double? importe})>(
    context,
    title: 'Mi sueldo',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Un importe fijo que te pagás cada sábado, como un empleado más. Lo de la casa y lo personal '
          'sale de ahí: anotá un retiro aparte solo cuando saques plata extra del negocio.',
        ),
        if (suggested != null) ...[
          const SizedBox(height: 8),
          Text(
            'Con lo que ganó el negocio, el sueldo sugerido es ${pesos(suggested)} por semana.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 12),
        moneyField(amount, 'Sueldo por semana', autofocus: true, helper: 'Dejalo vacío para no usar sueldo fijo.'),
        _error(error),
      ],
    ),
    onSave: (set) {
      final text = amount.text.trim();
      if (text.isEmpty) return (importe: null);
      final value = parseMoney(text);
      if (value == null || value <= 0) {
        set(() => error = 'Escribí el sueldo (mayor que 0) o dejalo vacío.');
        return null;
      }
      return (importe: value);
    },
  );
}

/// Pagarse el sueldo de una semana.
Future<FinRequest?> showPaySalaryForm(BuildContext context, SalaryStatus salary) {
  final amount = TextEditingController(text: importeEditable(salary.semanal ?? 0));
  var cuenta = efectivo;
  String? error;
  final week = salary.semana ?? DateTime.now();
  return _form<FinRequest>(
    context,
    title: 'Pagarme el sueldo',
    saveLabel: 'Pagado',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Semana del ${sabado(week)}.', style: const TextStyle(color: AppColors.gris)),
        const SizedBox(height: 12),
        moneyField(amount, 'Lo que te pagás', helper: 'Cambialo si esta semana es otro importe.'),
        const SizedBox(height: 12),
        const Text('Sale de', style: TextStyle(color: AppColors.gris)),
        const SizedBox(height: 4),
        accountPicker(cuenta, (v) => set(() => cuenta = v)),
        _error(error),
      ],
    ),
    onSave: (set) {
      final value = parseMoney(amount.text);
      if (value == null || value <= 0) {
        set(() => error = 'Escribí el importe (mayor que 0).');
        return null;
      }
      return FinRequest(
        'fin_pagar_sueldo',
        {'p_semana': isoDate(week), 'p_cuenta': cuenta, 'p_importe': value},
        'Mi sueldo · ${sabado(week)}',
        value,
      );
    },
  );
}

/// Cambiar de quién es un gasto o retiro ya anotado. Devuelve (de quién, categoría si es del negocio).
Future<({String deQuien, String? categoria})?> showReclassifyForm(BuildContext context, FinMovement m) {
  var owner = m.deQuien ?? 'negocio';
  String? categoria = m.tipo == 'gasto' && categoriasGasto.contains(m.categoria) ? m.categoria : null;
  String? error;
  return _form<({String deQuien, String? categoria})>(
    context,
    title: '¿De quién es?',
    saveLabel: 'Cambiar',
    body: (context, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${m.titulo} · ${pesos(-m.importe)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(diaMesHora(m.fecha), style: const TextStyle(color: AppColors.gris)),
        const SizedBox(height: 12),
        ownerPicker(owner, (v) => set(() => owner = v)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(ownerHelp(owner), style: const TextStyle(fontSize: 13, color: AppColors.gris)),
        ),
        if (owner == 'negocio') ...[
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
        _error(error),
      ],
    ),
    onSave: (set) {
      if (owner == 'negocio' && categoria == null) {
        set(() => error = 'Elegí en qué fue el gasto.');
        return null;
      }
      return (deQuien: owner, categoria: owner == 'negocio' ? categoria : null);
    },
  );
}

/// Alta o cambio de un gasto fijo. Devuelve los parámetros de fin_gasto_fijo_guardar (sin p_id).
Future<Map<String, dynamic>?> showFixedExpenseForm(BuildContext context, {FixedExpense? current}) {
  final name = TextEditingController(text: current?.nombre ?? '');
  final amount = TextEditingController(text: current == null ? '' : importeEditable(current.importe));
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
  final amount = TextEditingController(text: importeEditable(expense.importe));
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
  final total = TextEditingController(text: amount == null ? '' : importeEditable(amount));
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
  final amount = TextEditingController(text: importeEditable(debt.resta));
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
        set(() => error = 'Entre \$1 y ${pesos(debt.resta)}.');
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
