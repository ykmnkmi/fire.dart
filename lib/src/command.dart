import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:fire/src/exception.dart';

abstract class Mode implements Enum {
  String get description;
}

abstract class CliCommand extends Command<int> {
  CliCommand() {
    argParser.addFlag('verbose',
        negatable: false, help: 'Output more informational messages.');
  }

  @override
  late final ArgResults argResults =
      super.argResults ?? fail('Command is not called.');

  late final bool verbose = getBoolean('verbose') ?? false;

  late final bool version = getBoolean('version') ?? false;

  bool? getBoolean(String name) {
    return argResults[name] as bool?;
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

  T getMode<T extends Mode>(String name, List<T> values, T defaultValue) {
    var result = getString(name);

    if (result == null) {
      return defaultValue;
    }

    return values.byName(result);
  }

  List<String> getStrings(String name) {
    return argResults[name] as List<String>;
  }

  Future<int> handle();

  Future<void> cleanup() async {}

  @override
  void printUsage() {
    stdout.writeln(usage);
  }

  @override
  Future<int> run() async {
    try {
      return await handle();
    } finally {
      await cleanup();
    }
  }

  Never fail(String message) {
    throw CliException(message);
  }
}
