/// Uses the same two decimal places as contextual V2.
int? deliveryHundredths(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{0,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
}

({int original, int additional})? splitDeliveryQuantity(
  String input,
  int original, {
  required bool allowsAdditional,
}) {
  final total = deliveryHundredths(input);
  if (total == null || (total > original && !allowsAdditional)) return null;
  return total > original
      ? (original: original, additional: total - original)
      : (original: total, additional: 0);
}
