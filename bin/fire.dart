import 'dart:io'
    show Directory, File, FileSystemEntity, Platform, Process, StdinException, exit, stdin, stdout;

import 'package:frontend_server_client/frontend_server_client.dart' show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:watcher/watcher.dart' show DirectoryWatcher;

Future<void> main(
  final List<String> args,
) async {
  if (args.isEmpty) {
    _output("> usage: fire file.dart [arguments].");
    exit(1);
  } else {
    final file_path = args[0];
    if (FileSystemEntity.isFileSync(file_path)) {
      await run(
        file_path: file_path,
        output_path: path.setExtension(file_path, ".dill"),
        kernel_path: "lib/_internal/vm_platform_strong.dill",
        args: [
          if (args.isNotEmpty) ...args.sublist(1, args.length),
        ],
      );
    } else {
      _output("'" + file_path + "' not found or isn't a file.");
      exit(2);
    }
  }
}

// region internal
Future<void> run({
  required final String file_path,
  required final String output_path,
  required final String kernel_path,
  required final List<String> args,
}) async {
  final root = _find(
    file: File(file_path),
    // This constant was taken from `FrontendServerClient.start`s
    // packageJson parameters default value.
    target: ".dart_tool/package_config.json",
  );
  final FrontendServerClient client;
  try {
    client = await FrontendServerClient.start(
      file_path,
      output_path,
      kernel_path,
      packagesJson: root.target,
    );
  } on Object catch (error, stack_trace) {
    _output(error.toString());
    _output(Trace.format(stack_trace));
    exit(3);
  }
  final invalidated = <Uri>{};
  Future<void> watch(
    final Set<Uri> invalidated,
    final Directory dir,
  ) {
    final watcher = DirectoryWatcher(dir.absolute.path);
    watcher.events.listen((final event) {
      _output(event.toString());
      invalidated.add(path.toUri(event.path));
    });
    return watcher.ready;
  }

  // We assume that the lib directory can be found in
  // the directory where .dart_tool directory was found.
  final lib_directory = Directory(path.join(root.root.path, "lib"));
  if (lib_directory.existsSync()) {
    await watch(invalidated, lib_directory);
    _output("> watching lib folder.");
  } else {
    _output("> not watching the lib folder because it does not exist.");
  }
  Future<void> reload() async {
    try {
      final result = await client.compile(
        <Uri>[
          path.toUri(file_path),
          ...invalidated,
        ],
      );
      invalidated.clear();
      if (result.dillOutput == null) {
        _output("");
        _output("> no compilation result, rejecting.");
        return client.reject();
      } else if (result.errorCount > 0) {
        _output("> compiled with " + result.errorCount.toString() + " error(s).");
        return client.reject();
      } else {
        for (final line in result.compilerOutputLines) {
          _output(line);
        }
        client.accept();
        client.reset();
      }
    } on Object catch (error, trace) {
      _output(error.toString());
      _output(Trace.format(trace));
    }
  }

  Future<void> run() async {
    try {
      final result = await Process.run(
        path.normalize(Platform.resolvedExecutable),
        [
          output_path,
          ...args,
        ],
      );
      if (result.stdout != null) {
        _output(result.stdout.toString().trimRight());
      }
      if (result.stderr != null) {
        _output(result.stderr.toString().trimRight());
      }
    } on Object catch (error, trace) {
      _output(error.toString());
      _output(Trace.format(trace));
    }
  }

  final stopwatch = Stopwatch();
  _output("> compiling...");
  stopwatch.start();
  await reload();
  stopwatch.stop();
  _output("> compiling done, took " + stopwatch.elapsed.toString());
  stopwatch.reset();
  await run();
  _output("> press r to restart and q to exit.");
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
    const char_r = 114;
    const char_q = 113;
    const char_linefeed = 10;
    switch (bytes[0]) {
      case char_r:
        _output("> restarting...");
        stopwatch.start();
        await reload();
        stopwatch.stop();
        _output("> done, took " + stopwatch.elapsed.toString());
        stopwatch.reset();
        await run();
        break;
      case char_q:
        final exit_code = await client.shutdown();
        exit(exit_code);
      case char_linefeed:
        // We output a new line and not warn about unexpected input.
        // Why? It is common to 'spam' the terminal with
        // newlines to introduce a bunch of empty
        // lines as an ad-hoc way to clear the terminal.
        // These empty lines serve as a visual divider between
        // previous output and new output and improve the UX.
        _output("");
        break;
      default:
        final input = String.fromCharCodes(bytes);
        _output("> expected r to restart and q to exit, got '" + input + "'.");
    }
  }
}

_DiscoveredRoot _find({
  required final File file,
  required final String target,
}) {
  // Start out at the directive where the given file is contained.
  Directory current = file.parent.absolute;
  for (;;) {
    // Construct a candidate where the file we are looking for could be.
    final candidate = File(path.join(current.path, target));
    final file_found = candidate.existsSync();
    if (file_found) {
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
      final root_directory_reached = current == parent;
      if (root_directory_reached) {
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

void _output(
  final String line,
) {
  stdout.writeln(line);
}
// endregion
