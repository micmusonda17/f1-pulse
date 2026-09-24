import 'package:f1_pulse/screens/welcome_screen.dart';
import 'package:f1_pulse/utils/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('greetingFor', () {
    test('changes with the time of day', () {
      expect(
        greetingFor('Michael', now: DateTime(2026, 9, 24, 8)),
        'Good morning, Michael',
      );
      expect(
        greetingFor('Michael', now: DateTime(2026, 9, 24, 14)),
        'Good afternoon, Michael',
      );
      expect(
        greetingFor('Michael', now: DateTime(2026, 9, 24, 20)),
        'Good evening, Michael',
      );
    });

    test('leaves the name out when there is none', () {
      final morning = DateTime(2026, 9, 24, 8);
      expect(greetingFor(null, now: morning), 'Good morning');
      expect(greetingFor('   ', now: morning), 'Good morning');
    });
  });

  testWidgets('NamePage only lets you continue once you type a name',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose); // Clean up when the test ends
    var nextPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NamePage(
            controller: controller,
            onNext: () => nextPressed = true,
          ),
        ),
      ),
    );

    // No name yet: the Next button is switched off.
    await tester.tap(find.text('Next'));
    expect(nextPressed, isFalse);

    await tester.enterText(find.byType(TextField), 'Michael');
    await tester.pump(); // Draw the screen again with the new text
    await tester.tap(find.text('Next'));
    expect(nextPressed, isTrue);
  });
}
