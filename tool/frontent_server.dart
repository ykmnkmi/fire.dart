import 'dart:io';

import 'package:path/path.dart';

void main(List<String> arguments) {
  var dart = Platform.resolvedExecutable;
  var bin = dirname(dart);
  var snapshots = join(bin, 'snapshots');
  var snapshot = join(snapshots, 'frontend_server.dart.snapshot');
  var sdk = dirname(bin);
  var lib = join(sdk, 'lib');
  var internal = join(lib, '_internal');
  var dartdevcPlatform = toUri(join(internal, 'ddc_platform_sound.dill'));
  var vmPlatform = toUri(join(internal, 'vm_platform_strong.dill'));
  var packages = join('.dart_tool', 'package_config.json');

  var dartdevc = true;

  arguments = <String>[
    snapshot,
    '--sdk-root',
    sdk,
    '--platform',
    if (dartdevc) '$dartdevcPlatform' else '$vmPlatform',
    '--packages',
    packages,
    '--target',
    if (dartdevc) 'dartdevc' else 'vm',
    '--no-embed-source-text',
    '--sound-null-safety',
    '--no-emit-debug-symbols',
    '--no-print-incremental-dependencies',
    ...arguments,
  ];

  var result = Process.runSync(dart, arguments, //
      stdoutEncoding: null,
      stderrEncoding: null);
  stdout.add(result.stdout as List<int>);
  stderr.add(result.stderr as List<int>);
}
