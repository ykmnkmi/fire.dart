import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        Platform,
        Process,
        StdinException,
        exit,
        stdin,
        stdout;

import 'package:frontend_server_client/frontend_server_client.dart'
    show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:watcher/watcher.dart' show DirectoryWatcher;

const String kernel = 'lib/_internal/vm_platform_strong.dill';

final String dartExecutable = path.normalize(Platform.resolvedExecutable);
final String sdkDir = path.dirname(path.dirname(dartExecutable));

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stdout.writeln('> usage: fire file.dart [arguments].');
    exit(1);
  }

  final filePath = arguments[0];
  final fileUri = path.toUri(filePath);

  if (!FileSystemEntity.isFileSync(filePath)) {
    stdout.writeln('\'$filePath\' not found or is\'n a file.');
    exit(2);
  }

  final output = path.setExtension(filePath, '.dill');
  arguments[0] = output;

  FrontendServerClient client;

  final root = _find(
    file: File(filePath),
    // This constant was taken from `FrontendServerClient.start`s
    // packageJson parameters default value.
    target: '.dart_tool/package_config.json',
  );

  try {
    client = await FrontendServerClient.start(
      filePath,
      output,
      kernel,
      packagesJson: root.target,
    );
  } catch (error, stackTrace) {
    stdout.writeln(error);
    stdout.writeln(Trace.format(stackTrace));
    exit(3);
  }

  final invalidated = <Uri>{};

  Future<void> watch(Set<Uri> invalidated, Directory dir) {
    final watcher = DirectoryWatcher(dir.absolute.path);

    watcher.events.listen((event) {
      stdout.writeln(event);
      invalidated.add(path.toUri(event.path));
    });

    return watcher.ready;
  }

  // We assume that the lib directory can be found in
  // the directory where .dart_tool directory was found.
  final libDirectory = Directory(path.join(root.root.path, 'lib'));

  if (libDirectory.existsSync()) {
    await watch(invalidated, libDirectory);
    stdout.writeln('> watching lib folder.');
  } else {
    stdout.writeln('> not watching the lib folder because it does not exist.');
  }

  Future<void> reload() async {
    try {
      final result = await client.compile(<Uri>[fileUri, ...invalidated]);
      invalidated.clear();

      if (result.dillOutput == null) {
        stdout.writeln();
        stdout.writeln('> no compilation result, rejecting.');
        return client.reject();
      }

      if (result.errorCount > 0) {
        stdout.writeln('> compiled with ${result.errorCount} error(s).');
        return client.reject();
      }

      for (final line in result.compilerOutputLines) {
        stdout.writeln(line);
      }

      client.accept();
      client.reset();
    } catch (error, trace) {
      stdout.writeln(error);
      stdout.writeln(Trace.format(trace));
    }
  }

  Future<void> run() async {
    try {
      final result = await Process.run(dartExecutable, arguments);

      if (result.stdout != null) {
        stdout.writeln(result.stdout.toString().trimRight());
      }

      if (result.stderr != null) {
        stdout.writeln(result.stderr.toString().trimRight());
      }
    } catch (error, trace) {
      stdout.writeln(error);
      stdout.writeln(Trace.format(trace));
    }
  }

  final stopwatch = Stopwatch();
  stdout.write('> compiling...');
  stopwatch.start();
  await reload();
  stopwatch.stop();
  stdout.writeln('\r> compiling done, took ${stopwatch.elapsed}');
  stopwatch.reset();
  await run();
  stdout.writeln('> press r to restart and q to exit.');

  try {
    stdin.echoMode = false;
    stdin.lineMode = false;
  } on StdinException {
    // This exception is thrown when run via the intellij UI:
    // 'OS Error: Inappropriate ioctl for device, errno = 25'
    // We ignore this for now as disabling echoMode and lineMode
    // is 'nice to have' but not necessary.
  }

  await for (final bytes in stdin) {
    switch (bytes[0]) {
      case 114:
        stdout.write('> restarting...');
        stopwatch.start();
        await reload();
        stopwatch.stop();
        stdout.writeln('\r> done, took ${stopwatch.elapsed}');
        stopwatch.reset();
        await run();
        break;

      case 113:
        final exitCode = await client.shutdown();
        exit(exitCode);

      default:
        final input = String.fromCharCodes(bytes);
        stdout
            .writeln('> expected r to restart and q to exit, got \'$input\'.');
    }
  }
}

_DiscoveredRoot _find({
  required File file,
  required String target,
}) {
  // Start out at the directive where the given file is contained.
  var current = file.parent.absolute;

  for (;;) {
    // Construct a candidate where the file we are looking for could be.
    final candidate = File(path.join(current.path, target));
    final fileFound = candidate.existsSync();

    if (fileFound) {
      // If the file has been found, return its path.
      return _DiscoveredRoot(
        target: candidate.absolute.path,
        root: current.absolute,
      );
    } else {
      // The file has not been found.
      // Walk up the current directory until
      // the root directory has been reached
      final parent = current.parent;
      final rootDirectoryReached = current == parent;

      if (rootDirectoryReached) {
        // package_config not found.
        return _DiscoveredRoot(
          target: target,
          root: current.absolute,
        );
      } else {
        // Go to the parent until the
        // rootDirectory has been reached.
        current = parent;
      }
    }
  }
}

class _DiscoveredRoot {
  final String target;
  final Directory root;

  const _DiscoveredRoot({
    required this.target,
    required this.root,
  });
}
// ignore_for_file: avoid_print
