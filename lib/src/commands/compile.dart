import 'dart:io';

import 'package:fire/src/command.dart';
import 'package:fire/src/compiler.dart';
import 'package:path/path.dart';

class Compile extends CliCommand {
  Compile() {
    argParser
      ..addSeparator('Compile options:')
      ..addOption('output',
          abbr: 'o', help: 'Path to the output file.', valueHelp: 'file-path');
  }

  @override
  String get name {
    return 'compile';
  }

  @override
  String get description {
    return 'Compile Dart to Kernel snapshot.';
  }

  @override
  String get invocation {
    return '${super.invocation} <file-path>';
  }

  String get inputPath {
    var rest = argResults.rest;

    if (rest.length != 1) {
      usageException('message');
    }

    return rest[0];
  }

  String get outputPath {
    return getString('output') ?? setExtension(inputPath, '.dill');
  }

  @override
  Future<int> handle() async {
    var inputPath = this.inputPath;
    var outputPath = this.outputPath;

    var compiler = await Compiler.start(
      inputPath,
      outputPath,
      verbose: verbose,
    );

    var timer = Stopwatch();
    stdout.writeln('> Compiling ...');
    timer.start();

    int code;

    try {
      var result = await compiler.compile(const <String>{});
      timer.stop();

      if (result.isCompiled) {
        stdout.writeln('* Compiling done, took ${timer.elapsed}');
      } else if (result.output.isEmpty) {
        stdout
          ..writeln('* Compiling done, no compilation result')
          ..writeAll(result.output, '\n  ');
      } else {
        stdout
          ..writeln('* Compiling done, no compilation result:')
          ..writeAll(result.output, '\n  ');
      }

      await compiler.shutdown();
      code = 0;
    } catch (error, stackTrace) {
      stdout
        ..writeln(error)
        ..writeln(stackTrace);

      code = 1;
    }

    return code;
  }
}
