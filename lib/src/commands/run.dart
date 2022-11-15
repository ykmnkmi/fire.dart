import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fire/src/command.dart';
import 'package:fire/src/compiler.dart';
import 'package:path/path.dart';
import 'package:watcher/watcher.dart';

enum CleanMode {
  incremental,
  all,
}

enum RestartMode {
  manual,
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

  bool get watch {
    return getBoolean('watch');
  }

  CleanMode get clean {
    var clean = getString('clean');

    switch (clean) {
      case 'incremental':
        return CleanMode.incremental;
      case 'all':
        return CleanMode.all;
      default:
        throw UnsupportedError('CleanMode: $clean.');
    }
  }

  String get inputPath {
    var rest = argResults.rest;

    if (rest.isEmpty) {
      usageException('message');
    }

    return rest[0];
  }

  String get outputPath {
    return getString('output') ?? setExtension(inputPath, '.dill');
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
    var outputPath = this.outputPath;

    var compiler = await Compiler.start(
      inputPath,
      outputPath,
      verbose: verbose,
    );

    var invalidatedPaths = <String>{inputPath};
    var timer = Stopwatch();

    Future<void> compileKernel({bool reset = true}) async {
      if (invalidatedPaths.isEmpty) {
        if (reset) {
          compiler.reset();
        }

        return;
      }

      var prefix = reset ? '>' : '*';
      stdout.writeln('$prefix Compiling ...');
      timer.start();

      try {
        var result = await compiler.compile(invalidatedPaths, reset: reset);
        timer.stop();

        if (result.isCompiled) {
          stdout.writeln('* Compiling done, took ${timer.elapsed}');
          invalidatedPaths.clear();
        } else if (result.output.isEmpty) {
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
      }

      timer.reset();
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
      // TODO(*): log error
    }

    void restoreStdinMode() {
      try {
        stdin.lineMode = previousLineMode;

        if (previousLineMode) {
          stdin.echoMode = previousEchoMode;
        }
      } on StdinException {
        // TODO(*): log error
      }
    }

    group.add(stdin.map<String>(String.fromCharCodes));
    group.add(ProcessSignal.sigint.watch());

    if (isWithin('bin', inputPath)) {
      await watchFolder(group, 'bin');
    }

    if (isWithin('lib', inputPath)) {
      await watchFolder(group, 'lib', printIfNotPossible: true);
    } else {
      await watchFile(group, inputPath, printIfNotPossible: true);
    }

    if (isWithin('test', inputPath)) {
      await watchFolder(group, 'test');
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

          await compileKernel(reset: false);
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
    var outputPath = this.outputPath;

    switch (clean) {
      case CleanMode.all:
        var file = File(outputPath);

        if (file.existsSync()) {
          file.deleteSync();
        }

        continue incremental;

      incremental:
      case CleanMode.incremental:
        var file = File('$outputPath.incremental.dill');

        if (file.existsSync()) {
          file.deleteSync();
        }

        return;
    }
  }
}

bool isSourceEvent(WatchEvent event) {
  return event.path.endsWith('.dart');
}

Future<void> watchFile(
  StreamGroup<Object?> group,
  String file, {
  bool printIfNotPossible = false,
}) async {
  if (FileSystemEntity.isFileSync(file)) {
    var watcher = FileWatcher(file);
    group.add(watcher.events);
    // await watcher.ready;
    stdout.writeln("* Watching '$file' file.");
  } else if (printIfNotPossible) {
    stdout
      ..writeln('* Not watching the $file file.')
      ..writeln('  Because it does not exist or it is not a file.');
  }
}

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
      ..writeln('  Because it does not exist or it is not a folder.');
  }
}

void clearScreen() {
  if (Platform.isWindows) {
    // TODO(*): windows: reset buffer
    stdout.writeln('* Not supported yet.');
  } else if (stdout.supportsAnsiEscapes) {
    stdout.write('\x1b[2J\x1b[H');
  } else {
    stdout.writeln('* Not supported.');
  }
}

void printRunModeUsage({bool detailed = false}) {
  if (detailed) {
    // TODO(*): print detailed output
    return;
  }

  stdout
    ..writeln('🔥 To restart press "r".')
    ..writeln('   To quit, press "q" or "Q" for force quit.')
    ..writeln('   For a more detailed help message, press "h".')
    ..writeln();
}
