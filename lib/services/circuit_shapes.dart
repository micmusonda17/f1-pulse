import 'package:flutter/services.dart' show rootBundle;

import '../models/circuit_shape.dart';

/// Jolpica's circuit ids, and the id of the same circuit in the shapes file.
///
/// The two projects name circuits differently ("baku" and "az-2016"), so
/// this table joins them, like a dictionary in Python.
const Map<String, String> circuitShapeIds = {
  'albert_park': 'au-1953',
  'americas': 'us-2012',
  'bahrain': 'bh-2002',
  'baku': 'az-2016',
  'catalunya': 'es-1991',
  'estoril': 'pt-1972',
  'galvez': 'ar-1952',
  'hockenheimring': 'de-1932',
  'hungaroring': 'hu-1986',
  'imola': 'it-1953',
  'indianapolis': 'us-1909',
  'interlagos': 'br-1940',
  'istanbul': 'tr-2005',
  'jacarepagua': 'br-1977',
  'jeddah': 'sa-2021',
  'kyalami': 'za-1961',
  'losail': 'qa-2004',
  'madring': 'es-2026',
  'magny_cours': 'fr-1960',
  'marina_bay': 'sg-2008',
  'miami': 'us-2022',
  'monaco': 'mc-1929',
  'monza': 'it-1922',
  'mugello': 'it-1914',
  'nurburgring': 'de-1927',
  'portimao': 'pt-2008',
  'red_bull_ring': 'at-1969',
  'ricard': 'fr-1969',
  'rodriguez': 'mx-1962',
  'sepang': 'my-1999',
  'shanghai': 'cn-2004',
  'silverstone': 'gb-1948',
  'sochi': 'ru-2014',
  'spa': 'be-1925',
  'suzuka': 'jp-1962',
  'vegas': 'us-2023',
  'villeneuve': 'ca-1978',
  'watkins_glen': 'us-1956',
  'yas_marina': 'ae-2009',
  'zandvoort': 'nl-1948',
};

/// Loads the circuit shapes that ship inside the app.
///
/// The file is part of the app itself (an "asset", listed in pubspec.yaml),
/// so it works offline and on the website. We read it once and share it.
class CircuitShapes {
  CircuitShapes._();

  static final CircuitShapes instance = CircuitShapes._();

  static const String assetPath = 'assets/circuits/f1-circuits.geojson';

  Future<Map<String, CircuitShape>>? _loading;

  /// Every shape, keyed by the file's ids. Read from the file only once.
  Future<Map<String, CircuitShape>> load() {
    return _loading ??= _read();
  }

  Future<Map<String, CircuitShape>> _read() async {
    try {
      final text = await rootBundle.loadString(assetPath);
      return parseCircuitShapes(text);
    } catch (_) {
      return {}; // No shapes: the app simply leaves the drawings out
    }
  }

  /// The shape for a Jolpica circuit id, or null if we do not have one.
  Future<CircuitShape?> shapeFor(String circuitId) async {
    final fileId = circuitShapeIds[circuitId];
    if (fileId == null) return null;
    final shapes = await load();
    return shapes[fileId];
  }
}
