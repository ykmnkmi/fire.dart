import 'dart:io' show Directory, File, Platform, Process, ProcessResult, StdinException, exit, stdin;

import 'package:frontend_server_client/frontend_server_client.dart' show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:watcher/watcher.dart' show DirectoryWatcher;

// Run this command to active fire locally:
// > dart pub global activate fire.dart --source=path
Future<void> run_fire({
  required final String file_path,
  required final String output_path,
  required final String kernel_path,
  required final List<String> args,
  required final FireOutputDelegate output,
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
    output.output_error(error, stack_trace);
    exit(3);
  }
  final invalidated = <Uri>{};
  Future<void> watch(
    final Set<Uri> invalidated,
    final Directory dir,
  ) {
    final watcher = DirectoryWatcher(dir.absolute.path);
    watcher.events.listen((final event) {
      output.output_string(event.toString());
      invalidated.add(path.toUri(event.path));
    });
    return watcher.ready;
  }

  // We assume that the lib directory can be found in
  // the directory where the .dart_tool directory was found.
  final lib_directory = Directory(path.join(root.root.path, "lib"));
  if (lib_directory.existsSync()) {
    await watch(invalidated, lib_directory);
    output.output_string("> watching lib folder.");
  } else {
    output.output_string("> not watching the lib folder because it does not exist.");
  }
  Future<void> reload() async {
    final success = await () async {
      try {
        final result = await client.compile(
          <Uri>[
            path.toUri(file_path),
            ...invalidated,
          ],
        );
        invalidated.clear();
        if (result.dillOutput == null) {
          output.output_string("> no compilation result, rejecting.");
          return false;
        } else {
          if (result.errorCount > 0) {
            output.output_string("> ❌ compiled with " + result.errorCount.toString() + " error(s).");
            output.output_compiler_output(
              result.compilerOutputLines,
            );
            return false;
          } else {
            output.output_string("> ✅ compiled with no errors.");
            output.output_compiler_output(
              result.compilerOutputLines,
            );
            return true;
          }
        }
      } on Object catch (error, stack_trace) {
        output.output_error(error, stack_trace);
        return false;
      }
    }();
    if (success) {
      client.accept();
      client.reset();
    } else {
      await client.reject();
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
      output.redirect_process(result);
    } on Object catch (error, stack_trace) {
      output.output_error(error, stack_trace);
    }
  }

  output.output_string("> compiling...");
  output.output_string("> ...compiling done, took " + await _measure_in_ms(fn: reload));
  await run();
  output.output_string("> press r to restart and q to exit.");
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
    const char_q = 113;
    const char_r = 114;
    const char_s = 115;
    const char_linefeed = 10;
    switch (bytes[0]) {
      case char_q:
        // We quit fire on a single lowercase 'q'.
        final exit_code = await client.shutdown();
        exit(exit_code);
      restart:
      case char_r:
        // We restart the application on a single lowercase 'r'.
        output.output_string("> restarting...");
        output.output_string("> done, took " + await _measure_in_ms(fn: reload));
        await run();
        break;
      case char_s:
        // We clear the view slightly on a lowercase 's'
        // and continue with a lowercase 'r'.
        for (int i = 0; i < 10; i++) {
          output.output_string("");
        }
        continue restart;
      case char_linefeed:
        // We output a new line and don't warn about unexpected input.
        // Why? It is common to 'spam' the terminal with
        // newlines to introduce a bunch of empty
        // lines as an ad-hoc way to clear the terminal.
        // These empty lines serve as a visual divider between
        // previous output and new output which improves the UX.
        output.output_string("");
        break;
      default:
        final input = String.fromCharCodes(bytes);
        output.output_string("> expected r to restart and q to exit, got '" + input + "'.");
    }
  }
}

abstract class FireOutputDelegate {
  /// For warnings or informative messages.
  void output_string(
    final String str,
  );

  /// For caught errors.
  void output_error(
    final Object payload,
    final StackTrace stack_trace,
  );

  /// For compiler output.
  void output_compiler_output(
    final Iterable<String> values,
  );

  /// For [Process] output.
  void redirect_process(
    final ProcessResult result,
  );
}

// region internal
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

Future<String> _measure_in_ms({
  required final Future<void> Function() fn,
}) async {
  final stopwatch = Stopwatch();
  stopwatch.start();
  await fn();
  stopwatch.stop();
  final ms = (stopwatch.elapsed.inMicroseconds / 1000).toStringAsFixed(2) + " ms";
  stopwatch.reset();
  return ms;
}
// endregion
