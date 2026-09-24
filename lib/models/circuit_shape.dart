import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The shape of one circuit, plus a few facts about it.
///
/// It comes from assets/circuits/f1-circuits.geojson, a free map file
/// (MIT licence) that traces every circuit as a line of GPS points.
class CircuitShape {
  const CircuitShape({
    required this.id,
    required this.name,
    required this.lengthMetres,
    required this.firstGrandPrix,
    required this.points,
  });

  final String id; // The file's own id, like "az-2016"
  final String name;
  final int? lengthMetres;
  final int? firstGrandPrix; // The year of the first F1 race here
  final List<Offset> points; // x goes east, y goes north. Not pixels yet.

  /// "6.003 km", or null if the file has no length.
  String? get lengthText {
    final metres = lengthMetres;
    if (metres == null) return null;
    return '${(metres / 1000).toStringAsFixed(3)} km';
  }
}

/// Reads every circuit in a GeoJSON file, keyed by the file's ids.
///
/// GeoJSON is plain JSON with a fixed layout: a list of "features", each
/// with "properties" (facts) and a "geometry" (the shape). Our file uses
/// one LineString per circuit: a list of [longitude, latitude] pairs.
Map<String, CircuitShape> parseCircuitShapes(String geoJson) {
  final data = jsonDecode(geoJson) as Map<String, dynamic>;
  final features = data['features'] as List<dynamic>;

  final shapes = <String, CircuitShape>{};
  for (final feature in features.cast<Map<String, dynamic>>()) {
    final properties = feature['properties'] as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    if (geometry['type'] != 'LineString') continue; // Not a track outline

    final id = properties['id'] as String;
    shapes[id] = CircuitShape(
      id: id,
      name: (properties['Name'] as String?) ?? id,
      lengthMetres: (properties['length'] as num?)?.toInt(),
      firstGrandPrix: (properties['firstgp'] as num?)?.toInt(),
      points: flattenLonLat(geometry['coordinates'] as List<dynamic>),
    );
  }
  return shapes;
}

/// Turns [longitude, latitude] pairs into flat x and y values.
///
/// Lines of longitude get closer together as you move away from the
/// equator. At Silverstone one degree east is only 62% as far as one degree
/// north. So we shrink every longitude by cos(latitude), otherwise tracks
/// far from the equator would look stretched sideways.
List<Offset> flattenLonLat(List<dynamic> coordinates) {
  final pairs = coordinates.cast<List<dynamic>>();
  if (pairs.isEmpty) return [];

  // The track's middle latitude is close enough for the whole track.
  var latitudeTotal = 0.0;
  for (final pair in pairs) {
    latitudeTotal += (pair[1] as num).toDouble();
  }
  final middleLatitude = latitudeTotal / pairs.length;
  // cos() wants radians, not degrees: multiply by pi / 180 to convert.
  final squeeze = math.cos(middleLatitude * math.pi / 180);

  final points = <Offset>[];
  for (final pair in pairs) {
    final longitude = (pair[0] as num).toDouble();
    final latitude = (pair[1] as num).toDouble();
    points.add(Offset(longitude * squeeze, latitude));
  }
  return points;
}
