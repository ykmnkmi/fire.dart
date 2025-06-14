import 'dart:io';

import 'package:fire/src/command.dart';
import 'package:fire/src/compiler.dart';
import 'package:path/path.dart';

enum CompileTarget implements Mode {
  vm('lib/_internal/vm_platform_strong.dill', 'VM compilation target');

  const CompileTarget(this.platform, this.description);

  final String platform;

  @override
  final String description;

  static CompileTarget defaultMode = vm;
}

class Compile extends CliCommand {
  Compile() {
    argParser
      ..addSeparator('Compile options:')
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to the output file.',
        valueHelp: 'file-path',
      )
      ..addOption(
        'target',
        allowed: CompileTarget.values.names,
        allowedHelp: CompileTarget.values.describedMap,
        defaultsTo: CompileTarget.defaultMode.name,
        hide: true,
      )
      ..addFlag('quiet', negatable: false, help: 'Hide messages.');
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

  late final String inputPath = argResults.rest.length == 1
      ? argResults.rest.first
      : usageException('Input path required.');

  late final String outputPath =
      getString('output') ?? setExtension(inputPath, '.dill');

  late final CompileTarget target = getEnum(
    'target',
    CompileTarget.values,
    CompileTarget.vm,
  );

  late final bool notQuiet = !(getBoolean('quiet') ?? false);

  @override
  Future<int> handle() async {
    var compiler = await Compiler.start(
      inputPath,
      outputPath,
      platform: target.platform,
      target: target.name,
      verbose: notQuiet && verbose,
    );

    var timer = Stopwatch();
    stdout.writeln('> Compiling ...');
    timer.start();

    int code;

    try {
      var result = await compiler.compile(const <String>{});
      timer.stop();

      if (result.isCompiled) {
        if (notQuiet) {
          stdout.writeln('* Compiling done, took ${timer.elapsed}');
        }
      } else if (result.output.isEmpty) {
        if (notQuiet) {
          stdout.writeln('* Compiling done, no compilation result');
        }
      } else {
        if (notQuiet) {
          stdout
            ..writeln('* Compiling done, no compilation result:')
            ..writeAll(result.output, '\n');
        }
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
