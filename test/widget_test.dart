import 'package:f1_pulse/widgets/common_widgets.dart';
import 'package:f1_pulse/widgets/countdown.dart';
import 'package:f1_pulse/widgets/driver_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ErrorView shows the message and the retry button works',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorView(message: 'No internet', onRetry: () => retried = true),
        ),
      ),
    );

    expect(find.text('No internet'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('Countdown shows days, hours, minutes and seconds',
      (tester) async {
    final target = DateTime.now().add(
      const Duration(days: 2, hours: 3, minutes: 4, seconds: 30),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Countdown(target: target))),
    );

    expect(find.text('DAYS'), findsOneWidget);
    expect(find.text('02'), findsOneWidget); // 2 days
    expect(find.text('03'), findsOneWidget); // 3 hours
    expect(find.text('04'), findsOneWidget); // 4 minutes
  });

  testWidgets('DriverAvatar shows the driver code when there is no photo',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriverAvatar(photoUrl: null, colour: Colors.red, code: 'HAM'),
        ),
      ),
    );

    expect(find.text('HAM'), findsOneWidget);
  });
}
