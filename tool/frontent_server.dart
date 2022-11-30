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
  var vmPlatform = toUri(join(internal, 'vm_platform_strong.dill'));
  var packages = join('.dart_tool', 'package_config.json');

  arguments = <String>[
    snapshot,
    '--sdk-root',
    sdk,
    '--platform',
    '$vmPlatform',
    '--packages',
    packages,
    '--target',
    'vm',
    '--no-embed-source-text',
    '--sound-null-safety',
    '--no-emit-debug-symbols',
    '--no-print-incremental-dependencies',
    ...arguments,
  ];

  var result = Process.runSync(dart, arguments,
      stdoutEncoding: null, stderrEncoding: null);
  stdout.add(result.stdout as List<int>);
  stderr.add(result.stderr as List<int>);
}
