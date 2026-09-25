// Small helpers for reading and showing dates, times and numbers.
//
// We write these ourselves instead of adding a package, so you can see
// exactly how they work.

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Adds a leading zero: 7 becomes "07".
String twoDigits(int number) => number.toString().padLeft(2, '0');

/// "Sat 26 Sep, 13:00" in the phone's own time zone.
String formatDayTime(DateTime time) {
  final local = time.toLocal();
  final weekday = _weekdays[local.weekday - 1];
  final month = _months[local.month - 1];
  return '$weekday ${local.day} $month, '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

/// "26 Sep 2026"
String formatDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// "13:04:59" in the phone's own time zone.
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}';
}

/// "1:02:05" for 1 hour, 2 minutes and 5 seconds.
String formatElapsed(Duration duration) {
  final sign = duration.isNegative ? '-' : '';
  final d = duration.abs();
  return '$sign${d.inHours}:${twoDigits(d.inMinutes % 60)}:'
      '${twoDigits(d.inSeconds % 60)}';
}

/// "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago".
/// [now] is only there so the tests can pretend it is a certain time.
String formatTimeAgo(DateTime time, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(time);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes} min ago';
  if (difference.inDays < 1) return '${difference.inHours} h ago';
  if (difference.inDays == 1) return 'yesterday';
  return '${difference.inDays} days ago';
}

/// "Good morning, Michael". Without a name, just "Good morning".
/// [now] is only there so the tests can pretend it is a certain time.
String greetingFor(String? name, {DateTime? now}) {
  final hour = (now ?? DateTime.now()).hour;
  final String greeting; // final without a value: set once, below
  if (hour < 12) {
    greeting = 'Good morning';
  } else if (hour < 18) {
    greeting = 'Good afternoon';
  } else {
    greeting = 'Good evening';
  }
  final cleanName = name?.trim() ?? '';
  return cleanName.isEmpty ? greeting : '$greeting, $cleanName';
}

/// Points can be 25 or 12.5. Show "25", not "25.0".
String formatPoints(double points) {
  if (points == points.roundToDouble()) return points.toInt().toString();
  return points.toString();
}

/// Jolpica sends the date and the time separately:
/// date "2026-09-26" and time "11:00:00Z". We glue them together.
/// Very old seasons have no time, so we fall back to midday UTC.
DateTime? parseApiDateTime(Object? date, Object? time) {
  if (date is! String) return null;
  final clock = time is String ? time : '12:00:00Z';
  return DateTime.tryParse('${date}T$clock');
}

/// RSS feeds write dates like "Wed, 23 Sep 2026 11:27:50 +0000".
/// Dart cannot read that format on its own, so we take it apart by hand.
/// Returns the time in UTC, or null if the text is not a date we understand.
DateTime? parseRssDate(String? text) {
  if (text == null) return null;
  final parts = text.trim().split(RegExp(r'\s+'));
  // parts = ["Wed,", "23", "Sep", "2026", "11:27:50", "+0000"]
  if (parts.length < 5) return null;

  final month = _months.indexOf(parts[2]) + 1; // indexOf gives -1 if missing
  if (month == 0) return null;

  try {
    final day = int.parse(parts[1]);
    final year = int.parse(parts[3]);
    final clock = parts[4].split(':');
    if (clock.length < 2) return null;
    var result = DateTime.utc(
      year,
      month,
      day,
      int.parse(clock[0]),
      int.parse(clock[1]),
      clock.length > 2 ? int.parse(clock[2]) : 0,
    );

    // The last part is the time zone, like "+0200". Undo it to get UTC.
    if (parts.length > 5) {
      final zone = parts[5];
      final hasSign = zone.startsWith('+') || zone.startsWith('-');
      if (zone.length == 5 && hasSign) {
        final offset = Duration(
          hours: int.parse(zone.substring(1, 3)),
          minutes: int.parse(zone.substring(3, 5)),
        );
        result = zone.startsWith('+')
            ? result.subtract(offset)
            : result.add(offset);
      }
    }
    return result;
  } on FormatException {
    return null;
  }
}

/// A chance from 0 to 1 as a percentage: 0.4123 becomes "41%".
/// Tiny chances show as "<1%", because "0%" would mean impossible.
String formatChance(double chance) {
  final percent = (chance * 100).round();
  if (percent < 1) return '<1%';
  return '$percent%';
}

/// A lap time in seconds as the timing screen shows it: 92.456 becomes
/// "1:32.456". We work in whole milliseconds so 59.9996 becomes "1:00.000"
/// and never "0:60.000".
String formatLapTime(double seconds) {
  final millis = (seconds * 1000).round();
  final minutes = millis ~/ 60000;
  final wholeSeconds = (millis % 60000) ~/ 1000;
  final thousandths = (millis % 1000).toString().padLeft(3, '0');
  return '$minutes:${twoDigits(wholeSeconds)}.$thousandths';
}

/// "34:12" for 34 minutes and 12 seconds: the session clock in practice.
String formatMinutes(Duration duration) {
  final d = duration.isNegative ? Duration.zero : duration;
  return '${d.inMinutes}:${twoDigits(d.inSeconds % 60)}';
}

/// A chance as decimal odds, the way South African bookmakers show them:
/// a 40% chance is 2.50 (bet 1, get 2.50 back). Very long shots are "100+".
String formatOdds(double chance) {
  if (chance <= 0.01) return '100+';
  return (1 / chance).toStringAsFixed(2);
}

/// 0.25 as "25%", for rates like wins per start.
String formatRate(double rate) => '${(rate * 100).round()}%';
