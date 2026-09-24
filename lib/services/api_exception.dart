/// Thrown when one of our API calls fails.
///
/// The message is written for the person using the app, so a screen can
/// show it exactly as it is.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
