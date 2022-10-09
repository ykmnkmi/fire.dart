import 'dart:async';
import 'dart:io' show Directory, File, Platform, Process, ProcessResult, StdinException, exit, stdin;

import 'package:frontend_server_client/frontend_server_client.dart' show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:watcher/watcher.dart' show DirectoryWatcher;

// TODO finish building a testsuite.
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
  AutoRestartMode auto_restart_mode = AutoRestartMode.none;
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
  final platform_executable = path.normalize(Platform.resolvedExecutable);
  Future<void> restart_run({
    required final String prefix,
  }) async {
    Future<bool> _restart() async {
      try {
        final result = await client.compile(
          invalidated.toList(),
        );
        // Note calling client.reject seems to never work properly.
        // Calling 'accept' followed by a 'reset' seem to always
        // work correctly.
        client.accept();
        client.reset();
        invalidated.clear();
        if (result.dillOutput == null) {
          // It's not clear when this will happen.
          output.output_string("> no compilation result, rejecting.");
          return false;
        } else {
          if (result.errorCount > 0) {
            output.output_string("> ❌ compiled with " + result.errorCount.toString() + " error(s).");
            output.output_compiler_output(result.compilerOutputLines);
            return false;
          } else {
            output.output_string("> ✅ compiled with no errors.");
            output.output_compiler_output(result.compilerOutputLines);
            return true;
          }
        }
      } on Object catch (error, stack_trace) {
        // reject throws if a compilation failed.
        output.output_error(error, stack_trace);
        return false;
      }
    }

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

    Future<MapEntry<String, T>> _measure_in_ms<T>({
      required final Future<T> Function() fn,
    }) async {
      final stopwatch = Stopwatch();
      stopwatch.start();
      final result = await fn();
      stopwatch.stop();
      final ms = stopwatch.elapsed.inMicroseconds / 1000;
      stopwatch.reset();
      return MapEntry(ms.toStringAsFixed(2) + " ms", result);
    }

    output.output_string("> " + prefix + "...");
    final restart_duration = await _measure_in_ms(fn: _restart);
    output.output_string("> done, took " + restart_duration.key);
    if (restart_duration.value) {
      await run();
    }
  }

  // We assume that the lib directory can be found in
  // the directory where the .dart_tool directory was found.
  final lib_directory = Directory(path.join(root.root.path, "lib"));
  final is_watching = await () async {
    if (lib_directory.existsSync()) {
      final watcher = DirectoryWatcher(lib_directory.absolute.path);
      // We don't cancel the subscription here because it
      // doesn't matter for this terminal application.
      // ignore: unused_local_variable, cancel_subscriptions
      final subscription = watcher.events.listen((final event) {
        output.output_string("> " + event.toString());
        final invalidate = path.toUri(event.path);
        invalidated.add(invalidate);
        switch (auto_restart_mode) {
          case AutoRestartMode.none:
            break;
          case AutoRestartMode.on_entry_changed:
            if (file_path == event.path) {
              unawaited(restart_run(prefix: "auto restarting"));
            } else {
              // We stay on the safe side and only restart on
              // changes to the main script.
              // A restart on any unfiltered change could cascade into
              // infinite loops and other weird unexpected behaviors.
            }
            break;
        }
      });
      output.output_string("> watching lib directory.");
      await watcher.ready;
      return true;
    } else {
      output.output_string("> not watching the lib folder because it does not exist.");
      return false;
    }
  }();

  await restart_run(prefix: "compiling",);
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
    const char_m = 109;
    const char_n = 110;
    const char_q = 113;
    const char_r = 114;
    const char_s = 115;
    const char_linefeed = 10;
    switch (bytes[0]) {
      case char_d:
        // We print debug information on a lowercase 'd'.
        output.output_string("fire.dart debug state:");
        output.output_string("Arguments:");
        output.output_string(" • File path: " + file_path);
        output.output_string(" • Output path: " + output_path);
        output.output_string(" • Kernel path: " + kernel_path);
        output.output_string(" • Args: " + args.toString());
        output.output_string(" • Platform executable: " + platform_executable);
        // TODO use colors to make fire.dart output messages stand out from program and compiler output.
        output.output_string(" • Colorful output enabled: " + stdin.supportsAnsiEscapes.toString());
        output.output_string("Auto restarting:");
        output.output_string(" • Mode: " + auto_restart_mode.toString());
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
        // We hide some debug menus to not distract users.
        // ignore: prefer_const_declarations
        final show_hidden_options = false;
        if (show_hidden_options) {
          // Users usually won't need this.
          output.output_string(" - press 'd' to view debug information.");
          // THe terminal has its own way of exiting programs.
          output.output_string(" - press 'q' to quit fire.");
        }
        // The output below is roughly ordered by importance.
        output.output_string(" - press 'r' to hot restart.");
        output.output_string(" - press 's' to clear the screen and then hot restart.");
        output.output_string(" - press 'h' to output a tutorial.");
        output.output_string(" - press 'm' to enable auto restarting on a change to the main entry script.");
        output.output_string(" - press 'n' to disable auto restarting on a change to the main entry script.");
        break;
      case char_m:
        // On a lowercase 'm' we enable a mode where the whole program
        // is restarted when the main file has been modified.
        // 'm' and 'n' are separate commands and not a single toggle to
        // give each command idempotency which improves UX.
        switch (auto_restart_mode) {
          case AutoRestartMode.none:
            auto_restart_mode = AutoRestartMode.on_entry_changed;
            output.output_string("> Auto restart was enabled.");
            break;
          case AutoRestartMode.on_entry_changed:
            output.output_string("> Auto restart is already enabled.");
            break;
        }
        break;
      case char_n:
        // On a lowercase 'n' we disable the auto restart mode.
        // 'm' and 'n' are separate commands and not a single toggle to
        // give each command idempotency which improves UX.
        switch (auto_restart_mode) {
          case AutoRestartMode.none:
            output.output_string("> Auto restart is already disabled.");
            break;
          case AutoRestartMode.on_entry_changed:
            auto_restart_mode = AutoRestartMode.none;
            output.output_string("> Auto restart was disabled.");
            break;
        }
        break;
      case char_q:
        // We quit fire on a single lowercase 'q'.
        final exit_code = await client.shutdown();
        exit(exit_code);
      case char_r:
        await restart_run(prefix: "restarting");
        break;
      case char_s:
        // We clear the view slightly on a lowercase 's'
        // and continue with a lowercase 'r'.
        for (int i = 0; i < 10; i++) {
          output.output_string("");
        }
        await restart_run(prefix: "clear restarting");
        break;
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
        output.output_string(
          "> expected r to restart and q to exit, got '" + input + "'.",
        );
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
enum AutoRestartMode {
  /// Never restart automatically.
  none,

  /// Restart fire when the main file changed.
  on_entry_changed,
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
// endregion
