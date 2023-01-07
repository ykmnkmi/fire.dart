import 'dart:io';

import 'package:fire/fire.dart';

Future<void> main(List<String> args) async {
  exitCode = await FireCommandRunner().run(args);
  await Future.wait<void>(<Future<void>>[stdout.close(), stderr.close()]);
}
