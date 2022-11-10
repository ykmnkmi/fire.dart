// ignore_for_file: avoid_print

import 'dart:io';

import 'package:fire/fire.dart';
import 'package:path/path.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('> usage: fire file.dart [arguments].');
    exit(1);
  }

  var inputPath = normalize(arguments[0]);
  var inputType = FileSystemEntity.typeSync(inputPath);

  if (inputType != FileSystemEntityType.file) {
    print("'$inputPath' not found or isn't a file.");
    exit(2);
  }

  var outputPath = setExtension(inputPath, '.dill');

  var sdkPath = dirname(dirname(Platform.resolvedExecutable));
  var kernelPath = join(sdkPath, 'lib', '_internal', 'vm_platform_strong.dill');

  var verbose = true;

  Runner runner;

  try {
    runner = await Runner.start(
      inputPath,
      outputPath,
      kernelPath: kernelPath,
    );
  } catch (error, stackTrace) {
    print(error);

    if (verbose) {
      print(stackTrace);
    }

    exit(3);
  }

  // ...

  exitCode = await runner.shutdown();
}
