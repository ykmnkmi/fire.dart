import 'dart:io';
import 'dart:typed_data';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart';

class CompilerResult {
  CompilerResult({required this.isCompiled, this.output = const <String>[]});

  final bool isCompiled;

  final List<String> output;
}

class Compiler {
  Compiler(this.client);

  final FrontendServerClient client;

  Future<CompilerResult> compile(
    Set<String> invalidatedPath, {
    bool reset = true,
  }) async {
    var invalidatedUris = invalidatedPath.map<Uri>(toUri).toList();
    var result = await client.compile(invalidatedUris);
    var isCompiled = result.dillOutput != null && result.errorCount == 0;
    var outputLines = result.compilerOutputLines.toList();

    if (isCompiled) {
      client.accept();

      if (reset) {
        client.reset();
      }
    } else {
      await client.reject();
    }

    return CompilerResult(isCompiled: isCompiled, output: outputLines);
  }

  void accept() {
    client.accept();
  }

  void reset() {
    client.reset();
  }

  Future<void> reject() async {
    await client.reject();
  }

  Future<int> shutdown() {
    return client.shutdown();
  }

  static Future<Compiler> start(
    String inputPath,
    String outputPath, {
    String platform = 'lib/_internal/vm_platform_strong.dill',
    String target = 'vm',
    bool verbose = false,
  }) async {
    var sdkRoot = dirname(dirname(Platform.resolvedExecutable));

    var fileUri = toUri(absolute(inputPath));
    var packageConfig = await findPackageConfigUri(fileUri, loader: loader);

    if (packageConfig == null) {
      throw ArgumentError.value(inputPath, 'inputPath');
    }

    var package = packageConfig.packages.last;
    var packageRootPath = relative(fromUri(package.root));
    var packageConfigPath = join('.dart_tool', 'package_config.json');
    var packagesJsonPath = join(packageRootPath, packageConfigPath);

    var client = await FrontendServerClient.start(
      inputPath,
      outputPath,
      platform,
      packagesJson: packagesJsonPath,
      sdkRoot: sdkRoot,
      target: target,
      verbose: verbose,
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
