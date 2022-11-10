import 'dart:io';
import 'dart:typed_data';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart';

const String kernelPath = 'lib/_internal/vm_platform_strong.dill';

class Compiler {
  Compiler(this.client);

  final FrontendServerClient client;

  Future<bool> compile([List<Uri>? invalidatedUris]) async {
    var result = await client.compile(invalidatedUris);

    if (result.dillOutput == null) {
      await client.reject();
      return false;
    }

    if (result.errorCount > 0) {
      await client.reject();
      return false;
    }

    client.accept();
    return true;
  }

  Future<int> shutdown() {
    return client.shutdown();
  }

  static Future<Compiler> start(String inputPath, String outputPath) async {
    var fileUri = toUri(absolute(inputPath));
    var packageConfig = await findPackageConfigUri(fileUri, loader: loader);

    if (packageConfig == null) {
      // TODO(*): update error
      throw Exception('not found: $inputPath');
    }

    var package = packageConfig.packages.last;
    var packageRootPath = relative(fromUri(package.root));
    var packageConfigPath = join('.dart_tool', 'package_config.json');
    var packagesJsonPath = join(packageRootPath, packageConfigPath);

    var client = await FrontendServerClient.start(
      inputPath,
      outputPath,
      kernelPath,
      packagesJson: packagesJsonPath,
    );

    return Compiler(client);
  }
}

Future<Uint8List?> loader(Uri uri) async {
  var file = File.fromUri(uri);

  if (file.existsSync()) {
    return file.readAsBytesSync();
  }

  return null;
}
