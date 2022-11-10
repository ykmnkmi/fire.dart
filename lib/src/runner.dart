import 'dart:io';
import 'dart:typed_data';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart';

class Runner {
  Runner(this.client);

  final FrontendServerClient client;

  Future<void> run() async {
    throw UnimplementedError();
  }

  Future<int> shutdown() {
    return client.shutdown();
  }

  static Future<Runner> start(
    String inputPath,
    String outputPath, {
    required String kernelPath,
  }) async {
    inputPath = absolute(inputPath);
    outputPath = absolute(outputPath);

    var fileUri = toUri(inputPath);
    var packageConfig = await findPackageConfigUri(fileUri, loader: loader);

    if (packageConfig == null) {
      // TODO: update error
      throw Exception('not found: $inputPath');
    }

    var package = packageConfig.packages.last;
    var packageConfigPath =
        relative('.dart_rool/package_config.json', from: fromUri(package.root));

    var client = await FrontendServerClient.start(
      inputPath,
      outputPath,
      kernelPath,
      packagesJson: packageConfigPath,
    );

    return Runner(client);
  }
}

@internal
Future<Uint8List?> loader(Uri uri) async {
  var file = File.fromUri(uri);

  if (file.existsSync()) {
    return file.readAsBytesSync();
  }

  return null;
}
