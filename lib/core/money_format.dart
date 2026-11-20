import 'package:flutter/services.dart';

// Formato único de la plata en toda la app (pantallas, WhatsApp y PDF): $100.000, y los
// decimales solo si existen ($1.500,50).

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '') ?? 0;
}

/// 100000 → "100.000"; 1500.5 → "1.500,50"; 1500 → "1.500".
String formatoNumero(Object? value) {
  final v = _number(value);
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  final rest = cents % 100;
  final sign = v < 0 && cents > 0 ? '-' : '';
  return '$sign$whole${rest == 0 ? '' : ',${rest.toString().padLeft(2, '0')}'}';
}

/// 100000 → "$100.000"; 1500.5 → "$1.500,50"; −200 → "-$200".
String formatoPesos(Object? value) {
  final text = formatoNumero(value);
  return text.startsWith('-') ? '-\$${text.substring(1)}' : '\$$text';
}

/// "15000", "15.000", "15000,50", "15.000,50" o "$ 2.300.000" → número; vacío o inválido → null.
double? leerImporte(String text) {
  var t = text.trim().replaceAll('\$', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  }
  final value = double.tryParse(t);
  if (value == null || value.isNaN || value.isInfinite || value < 0) return null;
  return (value * 100).round() / 100;
}

/// Mientras se escribe un importe pone los puntos de miles (100.000) y deja hasta dos
/// decimales con coma. Un punto escrito al final se toma como coma decimal.
class ImporteInputFormatter extends TextInputFormatter {
  const ImporteInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text;
    final typedDot = raw.length == oldValue.text.length + 1 && raw.endsWith('.') && !raw.contains(',');
    if (typedDot) raw = '${raw.substring(0, raw.length - 1)},';
    // Pegado o escrito de una vez como "12.25": ese punto es la coma decimal.
    final decimalDot = RegExp(r'^(\d+)\.(\d{1,2})$').firstMatch(raw);
    if (decimalDot != null) raw = '${decimalDot[1]},${decimalDot[2]}';
    raw = raw.replaceAll(RegExp(r'[^0-9,]'), '');
    final comma = raw.indexOf(',');
    var whole = comma < 0 ? raw : raw.substring(0, comma);
    var decimals = comma < 0 ? null : raw.substring(comma + 1).replaceAll(',', '');
    whole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (decimals != null && decimals.length > 2) decimals = decimals.substring(0, 2);
    final grouped = whole.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
    final text = decimals == null ? grouped : '${grouped.isEmpty ? '0' : grouped},$decimals';
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Texto inicial de un campo de importe: 15000 → "15.000"; 0 o null → "".
String importeEditable(Object? value) {
  final v = _number(value);
  return v == 0 ? '' : formatoNumero(v);
}
