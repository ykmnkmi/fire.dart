import 'dart:io' as io show stdout, stderr;
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:fire/src/commands/compile.dart';
import 'package:fire/src/exception.dart';

ArgResults parseArguments(List<String> arguments) {
  var parser = ArgParser();
  return parser.parse(arguments);
}

class FireCommandRunner extends CommandRunner<int> {
  static const commandName = 'fire';

  static const commandDescription = 'Fast compiler for Dart CLI application.';

  FireCommandRunner({
    StringSink? stdout,
    StringSink? stderr,
  })  : output = io.stdout,
        stderr = io.stderr,
        super(commandName, commandDescription) {
    addCommand(Compile());
  }

  final StringSink output;

  final StringSink stderr;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      var code = await runCommand(parse(args));
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
