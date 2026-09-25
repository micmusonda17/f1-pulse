import 'package:flutter/material.dart';

import '../config.dart';
import '../models/standing.dart';
import '../services/app_preferences.dart';

/// A round driver photo with a ring in the team colour.
/// Shows the driver's code instead if there is no photo or it fails to load.
class DriverAvatar extends StatelessWidget {
  const DriverAvatar({
    super.key,
    required this.photoUrl,
    required this.colour,
    required this.code,
    this.size = 40,
  });

  final String? photoUrl;
  final Color colour;
  final String code; // "ANT", shown when there is no photo
  final double size;

  @override
  Widget build(BuildContext context) {
    // No photo on the public website (see AppConfig.showDriverPhotos), and
    // none with data saver on: every photo is a download.
    final url = AppConfig.showDriverPhotos && !AppPreferences.instance.dataSaver
        ? photoUrl
        : null;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias, // Cuts the square photo into a circle
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.35),
        border: Border.all(color: colour, width: 2),
      ),
      child: url == null
          ? _codeText()
          : Image.network(
              url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter, // Keep the face, not the chest
              // In a browser, let a plain <img> tag show photos from sites
              // that block apps from reading their images (CORS).
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (context, error, stackTrace) => _codeText(),
            ),
    );
  }

  Widget _codeText() {
    return Center(
      child: Text(
        code,
        style: TextStyle(
          fontSize: size * 0.28,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// A thin vertical bar in a team's colour, like the F1 TV graphics.
class TeamColourBar extends StatelessWidget {
  const TeamColourBar({super.key, required this.colour, this.height = 36});

  final Color colour;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// "Andrea Kimi ANTONELLI", the way F1 graphics write names.
/// A long name shrinks a little to fit, instead of being cut off.
Widget driverName(Driver driver, {TextStyle? style}) {
  return FittedBox(
    fit: BoxFit.scaleDown, // Only ever shrinks, never grows
    alignment: Alignment.centerLeft,
    child: Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '${driver.firstName} '),
          TextSpan(
            text: driver.lastName.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      maxLines: 1,
    ),
  );
}
