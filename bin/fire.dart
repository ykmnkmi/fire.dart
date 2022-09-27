import 'dart:io' show FileSystemEntity, exit;

import 'package:fire/fire.dart';
import 'package:path/path.dart' as path;

Future<void> main(
  final List<String> args,
) async {
  if (args.isEmpty) {
    print("> usage: fire file.dart [arguments].");
    exit(1);
  } else {
    final file_path = args[0];
    if (FileSystemEntity.isFileSync(file_path)) {
      await run_fire(
        file_path: file_path,
        output_path: path.setExtension(file_path, ".dill"),
        kernel_path: "lib/_internal/vm_platform_strong.dill",
        args: [
          if (args.isNotEmpty) ...args.sublist(1, args.length),
        ],
      );
    } else {
      print("'" + file_path + "' not found or isn't a file.");
      exit(2);
    }
  }
}
