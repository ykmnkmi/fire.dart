import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fire/src/commands/compile.dart';
import 'package:fire/src/commands/run.dart';
import 'package:fire/src/exception.dart';

class FireCommandRunner extends CommandRunner<int> {
  static const commandName = 'fire';

  static const commandDescription = 'Fast compiler for Dart CLI applications.';

  FireCommandRunner() : super(commandName, commandDescription) {
    addCommand(Run());
    addCommand(Compile());
  }

  @override
  String get invocation {
    return '$executableName <command> [options] input-file.dart';
  }

  @override
  void printUsage() {
    stdout.writeln(usage);
  }

  @override
  Future<int> run(Iterable<String> args) async {
    int code;

    try {
      var argsList = args.toList();
      var argResults = parse(argsList);
      //  ... error?
      code = await runCommand(argResults) ?? 1;
    } on CliException catch (error, stackTrace) {
      stdout
        ..writeln(error.message)
        ..writeln()
        ..writeln(stackTrace);

      code = 1;
    } on UsageException catch (error) {
      stdout
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);

      code = 64;
    }

    return code;
  }
}
