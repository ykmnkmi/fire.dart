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
  final client = await () async {
    try {
      return await FrontendServerClient.start(
        file_path,
        output_path,
        kernel_path,
        packagesJson: root.target,
      );
    } on Object catch (error, stack_trace) {
      output.output_error(error, stack_trace);
      return exit(3);
    }
  }();
  final invalidated = <Uri>{};
  // We assume that the lib directory can be found in
  // the directory where the .dart_tool directory was found.
  final lib_directory = Directory(path.join(root.root.path, "lib"));
  final is_watching = await () async {
    if (lib_directory.existsSync()) {
      final watcher = DirectoryWatcher(lib_directory.absolute.path);
      watcher.events.listen((final event) {
        output.output_string(event.toString());
        invalidated.add(path.toUri(event.path));
      });
      output.output_string("> watching lib directory.");
      await watcher.ready;
      return true;
    } else {
      output.output_string("> not watching the lib folder because it does not exist.");
      return false;
    }
  }();
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

  final platform_executable = path.normalize(Platform.resolvedExecutable);
  Future<void> run() async {
    try {
      final result = await Process.run(
        platform_executable,
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
  output.output_string("> press 'h' for a tutorial.");
  final did_disable_terminal_modes = () {
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
      return true;
    } on StdinException {
      // This exception is thrown when run via the intellij UI:
      // 'OS Error: Inappropriate ioctl for device, errno = 25'
      // We ignore this for now as disabling echoMode and lineMode
      // is 'nice to have' but not necessary.
      return false;
    }
  }();
  await for (final bytes in stdin) {
    const char_d = 100;
    const char_h = 104;
    const char_q = 113;
    const char_r = 114;
    const char_s = 115;
    const char_linefeed = 10;
    switch (bytes[0]) {
      case char_d:
        // We print debug information on a lowercase 'd'.
        output.output_string("fire.dart state:");
        output.output_string("Arguments:");
        output.output_string(" • File path: " + file_path);
        output.output_string(" • Output path: " + output_path);
        output.output_string(" • Kernel path: " + kernel_path);
        output.output_string(" • Args: " + args.toString());
        output.output_string(" • Platform executable: " + platform_executable);
        output.output_string("Root:");
        output.output_string(" • Detected root: " + root.root.toString());
        output.output_string(" • Detected package_config.json: " + root.target);
        output.output_string("Watcher:");
        output.output_string(" • Expected lib directory path: " + lib_directory.toString());
        output.output_string(" • Watching lib directory: " + is_watching.toString());
        output.output_string(" • Invalidated files (" + invalidated.length.toString() + "):");
        for (final uri in invalidated) {
          output.output_string("   - " + uri.toString());
        }
        output.output_string("Terminal:");
        output.output_string(" • Modes are set to false: " + did_disable_terminal_modes.toString());
        break;
      case char_h:
        // We print a tutorial on a lowercase 'h'.
        output.output_string("fire.dart tutorial:");
        output.output_string(" - press 'd' to view debug infomation.");
        output.output_string(" - press 'h' to output a tutorial.");
        output.output_string(" - press 'q' to quit fire.");
        output.output_string(" - press 'r' to hot restart.");
        output.output_string(" - press 's' to clear the screen and hot restart.");
        break;
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
