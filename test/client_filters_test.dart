import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/features/clients/client_filters.dart';
import 'package:distribuidora_alberdi/features/clients/visit_day_field.dart';
import 'package:distribuidora_alberdi/features/clients/client_multi_filter.dart';

void main() {
  test('Varias localidades y días se combinan con zona y búsqueda', () {
    final clientes = [
      {
        'nombre_comercio': 'Almacén A',
        'localidad': 'Ranchillos',
        'dia_visita': 6,
        'zona': 'Centro',
      },
      {
        'nombre_comercio': 'Almacén B',
        'localidad': 'Bella Vista',
        'dia_visita': 2,
        'zona': 'Centro',
      },
      {
        'nombre_comercio': 'Almacén C',
        'localidad': 'Ranchillos',
        'dia_visita': 1,
        'zona': 'Centro',
      },
      {
        'nombre_comercio': 'Almacén D',
        'localidad': 'Otra',
        'dia_visita': 6,
        'zona': 'Centro',
      },
      {
        'nombre_comercio': 'Almacén E',
        'localidad': 'Bella Vista',
        'dia_visita': 6,
        'zona': 'Rural',
      },
    ];
    final resultado = clientes
        .where(
          (c) => coincideCliente(
            c,
            localidades: {'ranchillos', 'bella vista'},
            dias: {2, 6},
            zona: 'centro',
            busqueda: 'almacen',
          ),
        )
        .toList();
    expect(resultado.map((c) => c['nombre_comercio']), [
      'Almacén A',
      'Almacén B',
    ]);
    expect(
      coincideCliente({}, localidades: {'', 'ranchillos'}, dias: {0, 6}),
      isTrue,
    );
    expect(clientes.where((c) => coincideCliente(c)).length, 5);
  });

  testWidgets('Selección múltiple conserva otras opciones y permite limpiar', (
    tester,
  ) async {
    var seleccion = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, cambiar) => ClientMultiFilter<int>(
              title: 'Días',
              allLabel: 'Todos los días',
              options: const {2: 'Martes', 6: 'Sábado'},
              selected: seleccion,
              onChanged: (valor) => cambiar(() => seleccion = valor),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Martes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sábado'));
    await tester.pumpAndSettle();
    expect(seleccion, {2, 6});
    await tester.tap(find.text('Martes'));
    await tester.pumpAndSettle();
    expect(seleccion, {6});
    await tester.tap(find.text('Todos los días'));
    await tester.pumpAndSettle();
    expect(seleccion, isEmpty);
  });

  final ranchillos = <String, dynamic>{
    'nombre_comercio': 'Almacén Ana',
    'localidad': ' Ranchillos ',
    'zona': ' CENTRO ',
    'dia_visita': 6,
  };
  test('Localidad, zona, día y búsqueda se combinan', () {
    expect(
      coincideCliente(
        ranchillos,
        localidades: {'ranchillos'},
        zona: 'centro',
        dias: {6},
        busqueda: 'almacen Ranchillos',
      ),
      isTrue,
    );
    expect(
      coincideCliente(ranchillos, localidades: {'ranchillos'}, dias: {1}),
      isFalse,
    );
    expect(coincideCliente(ranchillos, zona: 'rural'), isFalse);
    expect(coincideCliente(ranchillos, busqueda: 'ranchillos centro'), isTrue);
  });
  test('Sin asignar no se confunde con todos los días', () {
    expect(coincideCliente({}, dias: {0}, localidades: {''}, zona: ''), isTrue);
    expect(coincideCliente({}, dias: {6}), isFalse);
    expect(coincideCliente(ranchillos, dias: {0}), isFalse);
    expect(coincideCliente(ranchillos), isTrue);
    expect(nombreDiaVisita(null), 'Sin asignar');
  });
  test('Las opciones agrupan espacios, mayúsculas y acentos', () {
    expect(
      opcionesClientes([
        {'localidad': 'San Miguel'},
        {'localidad': ' SAN  MIGUEL '},
        {'localidad': 'San Miguél'},
        {'localidad': null},
      ], 'localidad').length,
      1,
    );
  });
  test('Editar un día cambia inmediatamente los resultados', () {
    final cliente = {...ranchillos};
    cliente['dia_visita'] = 1;
    expect(coincideCliente(cliente, dias: {6}), isFalse);
    expect(coincideCliente(cliente, dias: {1}), isTrue);
  });
  testWidgets('Día de visita permite asignar y quitar el sábado', (
    tester,
  ) async {
    int? seleccionado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisitDayField(
            value: null,
            onChanged: (dia) => seleccionado = dia,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sábado').last);
    await tester.pumpAndSettle();
    expect(seleccionado, 6);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin asignar').last);
    await tester.pumpAndSettle();
    expect(seleccionado, isNull);
  });
}
