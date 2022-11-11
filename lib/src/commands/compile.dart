import 'package:fire/src/command.dart';

class Compile extends CliCommand {
  Compile() {
    argParser
      ..addSeparator('Compile options:')
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

  String get inputPath {
    var rest = argResults.rest;

    if (rest.length != 1) {
      usageException('message');
    }

    return rest[0];
  }

  String? get outputPath {
    return getString('output');
  }

  @override
  Future<int> handle() async {
    print('output: $outputPath');
    return 0;
  }
}
