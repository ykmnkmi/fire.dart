import 'dart:io' as io show stdout, stderr;
import 'package:args/args.dart';
import 'package:args/command_runner.dart';

ArgResults parseArguments(List<String> arguments) {
  var parser = ArgParser()
    ..addSeparator('Global options')
    ..addFlag('help', abbr: 'h', negatable: true);

  return parser.parse(arguments);
}

class FireCommandRunner extends CommandRunner<int> {
  static const commandName = 'fire';

  static const commandDescription = 'Fast compiler for Dart CLI application.';

  FireCommandRunner({StringSink? stdout, StringSink? stderr})
      : output = io.stdout,
        stderr = io.stderr,
        super(commandName, commandDescription);

  final StringSink output;

  final StringSink stderr;
}
