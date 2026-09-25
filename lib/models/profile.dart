import 'dart:convert';

/// One person who uses Pitbeat on this phone.
///
/// Only the name and a colour live here. Everything else a person chooses
/// (favourite driver and team, fantasy team, betting stats) is saved under
/// keys that end in their id: see SettingsStore.profileId.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.colourIndex,
  });

  final String id; // Made from the moment it was created: "p1727254..."
  final String name;
  final int colourIndex; // Which of the profile colours it uses

  /// "Michael Musonda" becomes "MM", "Thandi" becomes "T".
  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    final letters = [
      for (final word in words.take(2))
        if (word.isNotEmpty) word[0].toUpperCase(),
    ];
    return letters.isEmpty ? '?' : letters.join();
  }

  Profile copyWith({String? name}) =>
      Profile(id: id, name: name ?? this.name, colourIndex: colourIndex);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'colour': colourIndex};

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      colourIndex: (json['colour'] as int?) ?? 0,
    );
  }
}

/// Every profile as one piece of JSON text, to save on the phone.
String encodeProfiles(List<Profile> profiles) =>
    jsonEncode([for (final profile in profiles) profile.toJson()]);

/// The saved text back into profiles. Missing or damaged text gives none.
List<Profile> decodeProfiles(String? text) {
  if (text == null || text.isEmpty) return [];
  try {
    final list = jsonDecode(text) as List<dynamic>;
    return [
      for (final item in list.cast<Map<String, dynamic>>())
        Profile.fromJson(item),
    ];
  } catch (_) {
    return [];
  }
}
