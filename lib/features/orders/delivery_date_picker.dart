import 'package:flutter/material.dart';

import '../../core/argentina_date_utils.dart';

Future<DateTime?> pickDeliveryDate(BuildContext context, {DateTime? selected}) {
  final now = ArgentinaDateUtils.ahoraArgentina();
  return showDatePicker(
    context: context,
    initialDate: selected,
    currentDate: DateTime(now.year, now.month, now.day),
    firstDate: DateTime(2020),
    lastDate: DateTime(now.year + 2, 12, 31),
    helpText: 'Elegí la fecha de entrega',
  );
}
