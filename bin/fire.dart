// ignore_for_file: avoid_print

import 'dart:io';

import 'package:fire/fire.dart';
import 'package:path/path.dart';

Future<void> main(List<String> arguments) async {
  String inputPath;
  String outputPath;

  switch (arguments.length) {
    case 1:
      inputPath = normalize(arguments[0]);
      outputPath = setExtension(inputPath, '.dill');
      break;
    case 2:
      inputPath = normalize(arguments[0]);
      outputPath = normalize(arguments[1]);
      break;
    default:
      print('> usage: fire file.dart [arguments].');
      exit(1);
  }

  var inputType = FileSystemEntity.typeSync(inputPath);

  if (inputType != FileSystemEntityType.file) {
    print("'$inputPath' not found or isn't a file.");
    exit(1);
  }

  Compiler compiler;

  try {
    compiler = await Compiler.start(inputPath, outputPath);
  } catch (error, stackTrace) {
    print(error);
    print(stackTrace);
    exit(1);
  }

  try {
    var invalidatedUris = <Uri>[toUri(inputPath)];
    await compiler.compile(invalidatedUris);
  } catch (error, stackTrace) {
    print(error);
    print(stackTrace);
    exit(1);
  }

  exitCode = await compiler.shutdown();
}
