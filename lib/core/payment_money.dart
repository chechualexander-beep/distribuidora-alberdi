/// Integer cents for display totals and validation. Failed reads never mean zero.
int paymentCents(Object? value) {
  final text = value?.toString().trim().replaceAll(',', '.') ?? '';
  if (!RegExp(r'^\d{1,12}(\.\d{1,4})?$').hasMatch(text)) {
    throw const FormatException('Importe monetario inválido.');
  }
  final parts = text.split('.');
  final fraction = parts.length == 1 ? '' : parts.last;
  if (fraction.length > 2 && fraction.substring(2).contains(RegExp('[1-9]'))) {
    throw const FormatException('El importe admite dos decimales.');
  }
  return int.parse(parts.first) * 100 +
      int.parse(fraction.padRight(2, '0').substring(0, 2));
}

String paymentMoney(Object? value) => centsMoney(paymentCents(value));
String centsMoney(int cents) =>
    '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
