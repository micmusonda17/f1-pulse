import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitbeat/services/app_preferences.dart';
import 'package:pitbeat/services/jolpica_api.dart';
import 'package:pitbeat/widgets/spoiler_gate.dart';

/// A pretend phone storage: a plain Map, so the tests need no plugins.
class MemoryCache implements ResponseCache {
  final Map<String, String> saved = {};

  @override
  Future<String?> read(String key) async => saved[key];

  @override
  Future<void> write(String key, String value) async {
    saved[key] = value;
  }
}

const scheduleJson = '''
{"MRData": {"RaceTable": {"Races": [
  {"season": "2026", "round": "1", "raceName": "Australian Grand Prix",
   "Circuit": {"circuitId": "albert_park", "circuitName": "Albert Park",
               "Location": {"locality": "Melbourne", "country": "Australia"}},
   "date": "2026-03-08", "time": "04:00:00Z"}
]}}}
''';

void main() {
  group('saved copies of Jolpica answers', () {
    late MemoryCache cache;
    var requests = 0;
    var online = true;

    // The pretend internet: counts requests, and fails when "offline".
    final client = MockClient((request) async {
      requests++;
      if (!online) throw http.ClientException('No signal');
      return http.Response(scheduleJson, 200);
    });

    setUp(() {
      cache = MemoryCache();
      JolpicaApi.cache = cache;
      requests = 0;
      online = true;
    });

    tearDown(() {
      JolpicaApi.cache = null;
      JolpicaApi.reuseCopiesFor = Duration.zero;
    });

    test('with no signal, the saved copy is used', () async {
      final api = JolpicaApi(client: client);
      await api.getSchedule(); // Online: saves a copy
      online = false;
      final races = await api.getSchedule(); // Offline: reads the copy
      expect(races.single.name, 'Australian Grand Prix');
    });

    test('data saver reuses a recent copy without downloading', () async {
      JolpicaApi.reuseCopiesFor = const Duration(minutes: 30);
      final api = JolpicaApi(client: client);
      await api.getSchedule();
      await api.getSchedule();
      expect(requests, 1); // The second answer came from the phone
    });
  });

  testWidgets('spoiler-free mode hides until you tap Show', (tester) async {
    AppPreferences.instance.spoilerFree = true;
    addTearDown(() => AppPreferences.instance.spoilerFree = false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SpoilerGate(
            topic: 'test',
            what: 'The results',
            child: Text('Antonelli wins'),
          ),
        ),
      ),
    );
    expect(find.text('Antonelli wins'), findsNothing);
    expect(find.text('The results may contain spoilers.'), findsOneWidget);

    await tester.tap(find.text('Show'));
    await tester.pump(); // Draw again after the tap
    expect(find.text('Antonelli wins'), findsOneWidget);
  });
}
