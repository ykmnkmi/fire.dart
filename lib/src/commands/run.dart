import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fire/src/command.dart';
import 'package:fire/src/compiler.dart';
import 'package:path/path.dart';
import 'package:watcher/watcher.dart';

/// Restart modes.
enum RestartMode {
  /// Restart manually.
  manual,

  /// Restart when the main file changed.
  onEntryChanged,
}

class Run extends CliCommand {
  Run() {
    argParser
      ..addSeparator('Run options:')
      ..addFlag('watch', //
          abbr: 'w',
          help: '',
          negatable: false)
      ..addOption('clean', //
          abbr: 'c',
          help: 'Clean produced files.',
          valueHelp: 'mode',
          allowed: <String>{'incremental', 'all'},
          defaultsTo: 'incremental')
      ..addOption('output', //
          abbr: 'o',
          help: 'Path to the output file.',
          valueHelp: 'file-path');
  }

  @override
  String get name {
    return 'run';
  }

  @override
  String get description {
    return 'Run Dart Kernel snapshot.';
  }

  @override
  String get invocation {
    return '${super.invocation} <file-path>';
  }

  String get inputPath {
    var rest = argResults.rest;

    if (rest.isEmpty) {
      usageException('message');
    }

    return rest[0];
  }

  bool get watch {
    return getBoolean('watch');
  }

  String? get clean {
    return getString('clean');
  }

  String? get outputPath {
    return getString('output');
  }

  List<String> get rest {
    var rest = argResults.rest;

    if (rest.length > 1) {
      return rest.sublist(1);
    }

    return <String>[];
  }

  @override
  Future<int> handle() async {
    var inputPath = this.inputPath;
    var outputPath = this.outputPath ?? setExtension(inputPath, '.dill');

    var compiler = await Compiler.start(inputPath, outputPath);
    var invalidatedPaths = <String>{inputPath};

    var timer = Stopwatch();

    Future<void> compileKernel({bool full = true}) async {
      if (invalidatedPaths.isEmpty) {
        if (full) {
          compiler.reset();
        }

        return;
      }

      var prefix = full ? '>' : '*';
      stdout.writeln('$prefix Compiling ...');
      timer.start();

      try {
        var result = await compiler.compile(invalidatedPaths, full: full);

        if (result.isCompiled) {
          stdout.writeln('* Compiling done, took ${timer.elapsed}');
          invalidatedPaths.clear();
          return;
        }

        if (result.output.isEmpty) {
          stdout
            ..writeln('* Compiling done, no compilation result')
            ..writeAll(result.output, '\n ');
        } else {
          stdout
            ..writeln('* Compiling done, no compilation result:')
            ..writeAll(result.output, '\n ');
        }
      } catch (error, stackTrace) {
        stderr
          ..writeln(error)
          ..writeln(stackTrace);
      } finally {
        timer
          ..stop()
          ..reset();
      }
    }

    var arguments = <String>[outputPath, ...rest];

    Future<int> runKernel() async {
      try {
        var result = await Process.run(Platform.executable, arguments);

        if (result.stdout is String) {
          var out = result.stdout as String;
          stdout.writeln(out.trimRight());
        }

        if (result.stderr is String) {
          var err = result.stderr as String;
          stderr.writeln(err.trimRight());
        }

        return result.exitCode;
      } catch (error, stackTrace) {
        stderr
          ..writeln(error)
          ..writeln(stackTrace);

        return 1;
      }
    }

    await compileKernel();
    await runKernel();

    if (!watch) {
      await compiler.shutdown();
      return 0;
    }

    var group = StreamGroup<Object?>();

    var previousEchoMode = stdin.echoMode;
    var previousLineMode = stdin.lineMode;

    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } on StdinException {
      // ...
    }

    void restoreStdinMode() {
      try {
        stdin.lineMode = previousLineMode;

        if (previousLineMode) {
          stdin.echoMode = previousEchoMode;
        }
      } on StdinException catch (error) {
        print(error);
      }
    }

    group.add(stdin.map<String>(String.fromCharCodes));
    group.add(ProcessSignal.sigint.watch());

    Future<void> watchFolder(
      StreamGroup<Object?> group,
      String folder, {
      bool printIfNotPossible = false,
    }) async {
      if (FileSystemEntity.isDirectorySync(folder)) {
        var watcher = DirectoryWatcher(folder);
        group.add(watcher.events.where(isSourceEvent));
        // await watcher.ready;
        stdout.writeln("* Watching '$folder' directory.");
      } else if (printIfNotPossible) {
        stdout
          ..writeln('* Not watching the $folder folder.')
          ..writeln('  Because it does not exist or it is not folder.');
      }
    }

    if (isWithin('bin', inputPath)) {
      await watchFolder(group, 'bin');
    }

    await watchFolder(group, 'lib', printIfNotPossible: true);

    if (isWithin('test', inputPath)) {
      await watchFolder(group, 'test');
    }

    final supportsAnsiEscapes = stdout.supportsAnsiEscapes;

    void clearScreen() {
      // ...
      if (supportsAnsiEscapes) {
        stdout.write('\x1b[2J\x1b[H');
      } else {
        stdout.writeln('* Not supported.');
      }
    }

    try {
      await for (var event in group.stream) {
        if (event == 'r') {
          stdout.writeln('> Restarting ...');
          await compileKernel();
          await runKernel();
          continue;
        }

        if (event is WatchEvent) {
          switch (event.type) {
            case ChangeType.ADD:
              stdout.writeln('* Add ${event.path}');
              invalidatedPaths.add(event.path);
              break;
            case ChangeType.MODIFY:
              stdout.writeln('* Modify ${event.path}');
              invalidatedPaths.add(event.path);
              break;
            case ChangeType.REMOVE:
              stdout.writeln('* Remove ${event.path}');
              invalidatedPaths.remove(event.path);
              break;
          }

          await compileKernel(full: false);
          continue;
        }

        if (event == 'q') {
          stdout.writeln('> Closing ...');
          restoreStdinMode();
          break;
        }

        if (event == 'Q' || event is ProcessSignal) {
          stdout.writeln('> Forse closing ...');
          restoreStdinMode();
          exit(0);
        }

        if (event == 's') {
          clearScreen();
          continue;
        }

        if (event == 'h') {
          stdout.writeln();
          printRunModeUsage();
          continue;
        }

        if (event == 'H') {
          stdout.writeln();
          printRunModeUsage(detailed: true);
          continue;
        }

        if (event is String) {
          stdout.writeln("* Unknown key: '$event'");
        } else {
          stdout.writeln('* Unknown event: $event');
        }
      }

      await group.close();
      await compiler.shutdown();
      return 0;
    } catch (error, stackTrace) {
      stderr
        ..writeln(error)
        ..writeln(stackTrace);

      return 1;
    }
  }

  @override
  Future<void> cleanup() async {
    var outputPath = this.outputPath ?? setExtension(inputPath, '.dill');

    switch (clean) {
      case 'all':
        var file = File(outputPath);

        if (file.existsSync()) {
          file.deleteSync();
        }

        continue incremental;

      incremental:
      case 'incremental':
        var file = File('$outputPath.incremental.dill');

        if (file.existsSync()) {
          file.deleteSync();
        }

        return;

      default:
        // ...
        throw UnsupportedError("Clean mode: '$clean'.");
    }
  }
}

bool isSourceEvent(WatchEvent event) {
  return event.path.endsWith('.dart');
}

void printRunModeUsage({bool detailed = false}) {
  if (detailed) {
    // ...
    return;
  }

  stdout
    ..writeln('🔥 To restart press "r".')
    ..writeln('   To quit, press "q" or "Q" for force quit.')
    ..writeln('   For a more detailed help message, press "h".')
    ..writeln();
}
