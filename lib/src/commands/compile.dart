import 'dart:io';

import 'package:fire/src/command.dart';
import 'package:fire/src/compiler.dart';
import 'package:path/path.dart';

class Compile extends CliCommand {
  Compile() {
    argParser
      ..addSeparator('Compile options:')
      ..addOption('target', //
          abbr: 't',
          help: 'Kernel target type.',
          valueHelp: 'mode',
          allowed: <String>{'dartdevc', 'vm'},
          defaultsTo: 'vm')
      ..addOption('output', //
          abbr: 'o',
          help: 'Path to the output file.',
          valueHelp: 'file-path');
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

  CompilerTarget get target {
    var target = getString('target');

    switch (target) {
      case 'dartdevc':
        return CompilerTarget.dartdevc;
      case 'vm':
        return CompilerTarget.vm;
      default:
        throw StateError('Unreachable.');
    }
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
      target: target,
      verbose: verbose,
    );

    var timer = Stopwatch();

    stdout.writeln('> Compiling ...');
    timer.start();

    try {
      var result = await compiler.compile(const <String>{});
      timer.stop();

      if (result.isCompiled) {
        stdout.writeln('* Compiling done, took ${timer.elapsed}');
      } else if (result.output.isEmpty) {
        stdout
          ..writeln('* Compiling done, no compilation result')
          ..writeAll(result.output, '\n ');
      } else {
        stdout
          ..writeln('* Compiling done, no compilation result:')
          ..writeAll(result.output, '\n ');
      }

      return 0;
    } catch (error, stackTrace) {
      stderr
        ..writeln(error)
        ..writeln(stackTrace);

      return 1;
    } finally {
      await compiler.shutdown();
    }
  }
}