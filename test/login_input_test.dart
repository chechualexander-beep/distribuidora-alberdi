import 'package:distribuidora_alberdi/main.dart' show LoginPage;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Contraseña conserva dígitos incrementales y pegados', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    final field = find.widgetWithText(TextField, 'Contraseña');
    await tester.showKeyboard(field);
    final widget = tester.widget<TextField>(field);
    expect(widget.obscureText, isTrue);
    const fixture = 'qa7B3';
    for (var count = 1; count <= fixture.length; count++) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: fixture.substring(0, count),
          selection: TextSelection.collapsed(offset: count),
        ),
      );
      await tester.pump();
      expect(widget.controller!.text == fixture.substring(0, count), isTrue);
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': 'x2'};
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    await editable.pasteText(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(widget.controller!.text == '${fixture}x2', isTrue);
  });
}
