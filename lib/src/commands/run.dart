import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fire/src/command.dart';
import 'package:fire/src/compiler.dart';
import 'package:fire/src/exception.dart';
import 'package:path/path.dart';
import 'package:radix_tree/radix_tree.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

enum CleanMode implements Mode {
  all('Delete all generated files.'),
  incremental('Delete only incremental files.'),
  keep('Keep all generated files.');

  const CleanMode(this.description);

  @override
  final String description;

  static CleanMode defaultMode = incremental;
}

enum RestartMode implements Mode {
  onEntryChanged('Restart by watcher or manually.'),
  manual('Restart manually.');

  const RestartMode(this.description);

  @override
  final String description;

  static RestartMode defaultMode = onEntryChanged;
}

class Run extends CliCommand {
  Run() {
    argParser
      ..addSeparator('Run options:')
      ..addFlag('watch', abbr: 'w', help: 'Enable watcher.', negatable: false)
      ..addMultiOption(
        'watch-entry',
        abbr: 'W',
        help: 'Entry to watch.',
        defaultsTo: <String>['lib'],
      )
      ..addFlag('run-in-shell', help: 'Run in shell.', negatable: false)
      ..addOption(
        'restart-mode',
        help: 'Watch restart mode.',
        valueHelp: 'mode',
        allowed: RestartMode.values.names,
        allowedHelp: RestartMode.values.describedMap,
        defaultsTo: RestartMode.defaultMode.name,
      )
      ..addOption(
        'clean',
        help: 'Clean produced files.',
        valueHelp: 'mode',
        allowed: CleanMode.values.names,
        allowedHelp: CleanMode.values.describedMap,
        defaultsTo: CleanMode.defaultMode.name,
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to the kernel file.',
        valueHelp: 'file-path',
      );
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

  late final bool runInShell = getBoolean('run-in-shell') ?? false;

  late final bool watch = getBoolean('watch') ?? false;

  late final List<String> watchEntries = getStrings('watch-entry');

  late final RestartMode restartMode = getEnum<RestartMode>(
    'restart-mode',
    RestartMode.values,
    RestartMode.defaultMode,
  );

  late final CleanMode clean = getEnum<CleanMode>(
    'clean',
    CleanMode.values,
    CleanMode.defaultMode,
  );

  String get inputPath {
    var rest = argResults.rest;

    if (rest.isEmpty) {
      usageException('No input file.');
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

    if (!FileSystemEntity.isFileSync(inputPath)) {
      throw CliException("Input file '$inputPath' not found.");
    }

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
            ..writeAll(result.output, '\n  ');
        } else {
          stdout
            ..writeln('* Compiling done, no compilation result:')
            ..writeAll(result.output, '\n  ');
        }
      } catch (error, stackTrace) {
        stdout
          ..writeln(error)
          ..writeln(stackTrace);
      }

      timer.reset();
    }

    var arguments = <String>[outputPath, ...rest];
    var runInShell = this.runInShell;

    Future<int> runKernel() async {
      int code;

      try {
        var result = await Process.run(
          Platform.executable,
          arguments,
          runInShell: runInShell,
        );

        if (result.stdout is String) {
          var out = result.stdout as String;
          stdout.writeln(out.trimRight());
        }

        if (result.stderr is String) {
          var err = result.stderr as String;
          stdout.writeln(err.trimRight());
        }

        code = result.exitCode;
      } catch (error, stackTrace) {
        stdout
          ..writeln(error)
          ..writeln(stackTrace);

        code = 1;
      }

      return code;
    }

    await compileKernel();
    await runKernel();

    if (!watch) {
      return await compiler.shutdown();
    }

    var group = StreamGroup<Object?>();

    var previousEchoMode = stdin.echoMode;
    var previousLineMode = stdin.lineMode;

    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } on StdinException {
      // TODO(*): log error.
    }

    void restoreStdinMode() {
      try {
        stdin.lineMode = previousLineMode;

        if (previousLineMode) {
          stdin.echoMode = previousEchoMode;
        }
      } on StdinException {
        // TODO(*): log error.
      }
    }

    group.add(stdin.map<String>(String.fromCharCodes));
    group.add(ProcessSignal.sigint.watch());

    var restartOnInputChange = restartMode == RestartMode.onEntryChanged;

    {
      var tree = RadixTree<String>();
      tree[inputPath] = inputPath;

      for (var entry in watchEntries) {
        tree[entry] = entry;
      }

      // TODO(radix_tree): remove ignore.
      // ignore: invalid_use_of_internal_member
      for (var node in tree.root.children) {
        // TODO(radix_tree): remove ignore.
        // ignore: invalid_use_of_internal_member
        var path = node.value!;

        if (FileSystemEntity.isFileSync(path)) {
          await watchFile(group, path);
        } else if (FileSystemEntity.isDirectorySync(path)) {
          await watchFolder(group, path);
        } else {
          throw CliException('Unsupported entry: $path');
        }
      }
    }

    int code;

    try {
      printRunModeUsage();

      Future<void> restart() async {
        await compileKernel();
        await runKernel();
      }

      await for (var event in group.stream) {
        if (event == 'r') {
          await restart();
        } else if (event is WatchEvent) {
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

          if (restartOnInputChange && equals(event.path, inputPath)) {
            await restart();
          }
        } else if (event == 'q') {
          stdout.writeln('> Closing ...');
          restoreStdinMode();
          break;
        } else if (event == 'Q' || event is ProcessSignal) {
          stdout.writeln('> Forse closing ...');
          restoreStdinMode();
          exit(0);
        } else if (event == 's') {
          clearScreen();
        } else if (event == 'S') {
          clearScreen();
          await restart();
        } else if (event == 'h') {
          stdout.writeln('');
          printRunModeUsage();
        } else if (event == 'H') {
          stdout.writeln('');
          printRunModeUsage(detailed: true);
        } else if (event is String) {
          stdout.writeln("* Unknown key: '$event'");
        } else {
          stdout.writeln('* Unknown event: $event');
        }
      }

      await group.close();
      await compiler.shutdown();
      code = 0;
    } catch (error, stackTrace) {
      stdout
        ..writeln(error)
        ..writeln(stackTrace);

      code = 1;
    }

    return code;
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

      case CleanMode.keep:
        // Do nothing.
        break;
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
      ..writeln("* Can't watching the '$file' file.")
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
    group.add(watcher.events.debounce(Duration.zero).where(isSourceEvent));
    // await watcher.ready;
    stdout.writeln("* Watching '$folder' directory.");
  } else if (printIfNotPossible) {
    stdout
      ..writeln("* Can't watching the '$folder' folder.")
      ..writeln('  Because it does not exist or it is not a folder.');
  }
}

void clearScreen() {
  if (stdout.supportsAnsiEscapes) {
    stdout.write('\x1b[2J\x1b[H');
  } else if (Platform.isWindows) {
    // TODO(*): windows: reset buffer.
    stdout.writeln('* Not yet supported.');
  } else {
    stdout.writeln('* Not supported.');
  }
}

void printRunModeUsage({bool detailed = false}) {
  stdout
    ..writeln('* To restart press "r".')
    ..writeln('  Press "q" to quit or "Q" to force quit.');

  if (detailed) {
    stdout.writeln('  Press "s" to clear or "S" to restart after.');
  } else {
    stdout.writeln('  For a more detailed help message, press "H".');
  }

  stdout.writeln();
}
