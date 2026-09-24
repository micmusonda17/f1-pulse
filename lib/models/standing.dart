/// A driver, as Jolpica describes them.
class Driver {
  const Driver({
    required this.id,
    required this.code,
    required this.number,
    required this.firstName,
    required this.lastName,
    required this.nationality,
  });

  final String id; // "antonelli"
  final String code; // "ANT"
  final String number; // "12". Empty for some older drivers.
  final String firstName;
  final String lastName;
  final String nationality;

  String get fullName => '$firstName $lastName';

  factory Driver.fromJson(Map<String, dynamic> json) {
    final lastName = json['familyName'] as String;
    // Older drivers have no three-letter code, so we make one.
    final madeUpCode = lastName.length >= 3
        ? lastName.substring(0, 3).toUpperCase()
        : lastName.toUpperCase();
    return Driver(
      id: json['driverId'] as String,
      code: (json['code'] as String?) ?? madeUpCode,
      number: (json['permanentNumber'] as String?) ?? '',
      firstName: json['givenName'] as String,
      lastName: lastName,
      nationality: (json['nationality'] as String?) ?? '',
    );
  }
}

/// One row of the drivers' championship table.
class DriverStanding {
  const DriverStanding({
    required this.position,
    required this.points,
    required this.wins,
    required this.driver,
    required this.team,
  });

  final int position;
  final double points; // double because half points exist
  final int wins;
  final Driver driver;
  final String team;

  factory DriverStanding.fromJson(Map<String, dynamic> json) {
    final constructors = json['Constructors'] as List<dynamic>;
    // A driver who changed team mid-season has two. We show the latest.
    final team = constructors.isEmpty
        ? ''
        : (constructors.last as Map<String, dynamic>)['name'] as String;
    return DriverStanding(
      position: int.tryParse('${json['position']}') ?? 0,
      points: double.parse(json['points'] as String),
      wins: int.parse(json['wins'] as String),
      driver: Driver.fromJson(json['Driver'] as Map<String, dynamic>),
      team: team,
    );
  }
}

/// One row of the constructors' (teams') championship table.
class ConstructorStanding {
  const ConstructorStanding({
    required this.position,
    required this.points,
    required this.wins,
    required this.name,
    required this.nationality,
  });

  final int position;
  final double points;
  final int wins;
  final String name;
  final String nationality;

  factory ConstructorStanding.fromJson(Map<String, dynamic> json) {
    final constructor = json['Constructor'] as Map<String, dynamic>;
    return ConstructorStanding(
      position: int.tryParse('${json['position']}') ?? 0,
      points: double.parse(json['points'] as String),
      wins: int.parse(json['wins'] as String),
      name: constructor['name'] as String,
      nationality: (constructor['nationality'] as String?) ?? '',
    );
  }
}
