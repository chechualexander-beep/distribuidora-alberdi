import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:distribuidora_alberdi/core/desktop_records.dart';
import 'package:distribuidora_alberdi/features/commissions/commission_groups_table.dart';

void main() {
  void size(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(
    Widget child, {
    TargetPlatform platform = TargetPlatform.windows,
  }) => MaterialApp(
    key: ValueKey(platform),
    theme: ThemeData(platform: platform),
    home: Scaffold(body: child),
  );

  testWidgets(
    'Seleccionar y editar no abre la fila; abrir conserva el registro',
    (tester) async {
      size(tester, 1200);
      final record = <String, dynamic>{'id': 'a', 'nombre': 'Cliente A'};
      DesktopRecord? opened;
      var selected = false;
      var edits = 0;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => DesktopRecords(
              records: [record],
              fields: [DesktopField('Cliente', (r) => r['nombre'])],
              leading: (r) => Checkbox(
                value: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              actions: (r) => IconButton(
                tooltip: 'Editar',
                onPressed: () => edits++,
                icon: const Icon(Icons.edit),
              ),
              onOpen: (r) => opened = r,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(selected, isTrue);
      expect(opened, isNull);
      await tester.tap(find.byTooltip('Editar'));
      expect(edits, 1);
      expect(opened, isNull);
      await tester.tap(find.text('Cliente A'));
      expect(identical(opened, record), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tabla incrustada permite desplazamiento lateral en un panel estrecho',
    (tester) async {
      size(tester, 900);
      await tester.pumpWidget(
        app(
          Row(
            children: [
              const SizedBox(width: 220),
              Expanded(
                child: ListView(
                  children: [
                    DesktopRecords(
                      embedded: true,
                      records: [
                        {
                          'nombre': 'Producto largo',
                          'observacion': 'Revisar entrega',
                        },
                      ],
                      fields: [
                        DesktopField(
                          'Producto',
                          (r) => r['nombre'],
                          width: 300,
                        ),
                        DesktopField(
                          'Observación',
                          recordObservation,
                          width: 180,
                        ),
                        DesktopField(
                          'Última columna',
                          (r) => 'Final',
                          width: 240,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.byTooltip('Revisar entrega'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final horizontal = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      await tester.drag(horizontal, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Final').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Formulario en dos columnas conserva texto al volver al diseño móvil',
    (tester) async {
      size(tester, 1200);
      final a = TextEditingController();
      final b = TextEditingController();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      Widget form() => DesktopFormList(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Cliente'),
          TextFormField(
            controller: a,
            decoration: const InputDecoration(labelText: 'Comercio'),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: b,
            decoration: const InputDecoration(labelText: 'Dirección'),
          ),
        ],
      );
      await tester.pumpWidget(app(form()));
      final fields = find.byType(TextFormField);
      expect(
        tester.getTopLeft(fields.first).dy,
        tester.getTopLeft(fields.last).dy,
      );
      await tester.enterText(fields.first, 'Almacén');
      await tester.enterText(fields.last, 'San Martín 100');
      await tester.pumpWidget(app(form(), platform: TargetPlatform.android));
      expect(
        tester.getTopLeft(fields.last).dy,
        greaterThan(tester.getTopLeft(fields.first).dy),
      );
      expect(a.text, 'Almacén');
      expect(b.text, 'San Martín 100');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Comisiones muestran los mismos importes y permiten abrir el detalle',
    (tester) async {
      size(tester, 1500);
      await tester.pumpWidget(
        app(
          ListView(
            children: [
              CommissionGroupsTable(
                groups: {
                  'pedido01': [
                    {
                      'pedidos': {
                        'clientes': {'nombre_comercio': 'Almacén'},
                      },
                      'productos': {'nombre': 'Producto'},
                      'cantidad': 5,
                      'cantidad_entregada': 3,
                      'cantidad_no_entregada': 2,
                      'precio_unitario': 100,
                      'porcentaje_comision': 10,
                      'importe_comision': 30,
                    },
                  ],
                },
              ),
            ],
          ),
        ),
      );
      expect(find.text(r'$500,00'), findsOneWidget);
      expect(find.text(r'$300,00'), findsOneWidget);
      expect(find.text(r'$200,00'), findsOneWidget);
      expect(find.text(r'$30,00'), findsOneWidget);
      await tester.tap(find.text('Almacén'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Producto').last, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
