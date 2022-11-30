import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fire/src/commands/compile.dart';
import 'package:fire/src/commands/run.dart';
import 'package:fire/src/exception.dart';

class FireCommandRunner extends CommandRunner<int> {
  static const commandName = 'fire';

  static const commandDescription = 'Fast compiler for Dart CLI application.';

  FireCommandRunner() : super(commandName, commandDescription) {
    addCommand(Run());
    addCommand(Compile());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      var argsList = args.toList();
      var argResults = parse(argsList);
      var code = await runCommand(argResults);
      //  ... error?
      return code ?? 1;
    } on CliException catch (error, stackTrace) {
      stderr
        ..writeln(error.message)
        ..writeln()
        ..writeln(stackTrace);

      return 1;
    } on UsageException catch (error) {
      stderr
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);

      return 64;
    }
  }
}
