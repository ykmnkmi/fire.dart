import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:fire/src/exception.dart';

/// A CLI command.
abstract class CliCommand extends Command<int> {
  CliCommand() {
    argParser
      ..addFlag('version', negatable: false, help: 'Print this tool version.')
      ..addFlag('verbose',
          abbr: 'v',
          negatable: false,
          help: 'Output more informational messages.');
  }

  @override
  ArgResults get argResults {
    var argResults = super.argResults;

    if (argResults == null) {
      throw CliException('Command is not called.');
    }

    return argResults;
  }

  bool get verbose {
    return getBoolean('verbose');
  }

  bool get version {
    return getBoolean('version');
  }

  bool getBoolean(String name) {
    return argResults[name] as bool? ?? false;
  }

  int? getInteger(String name) {
    var value = argResults[name] as String?;

    if (value == null) {
      return null;
    }

    return int.parse(value);
  }

  String? getString(String name) {
    return argResults[name] as String?;
  }

  Future<int> handle();

  Future<void> cleanup() async {}

  @override
  Future<int> run() async {
    try {
      return await handle();
    } finally {
      await cleanup();
    }
  }
}
