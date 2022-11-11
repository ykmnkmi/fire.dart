/// A exception thrown by CLI.
class CliException implements Exception {
  CliException(this.message);

  final String message;
}
