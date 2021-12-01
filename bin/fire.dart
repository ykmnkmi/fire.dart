import 'dart:io' show FileSystemEntity, Platform, Process, exit, stdin, stdout;

import 'package:frontend_server_client/frontend_server_client.dart'
    show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:watcher/watcher.dart' show Watcher;

const String kernel = 'lib/_internal/vm_platform_strong.dill';

late final String dartExecutable = path.normalize(Platform.resolvedExecutable);
late final String sdkDir = path.dirname(path.dirname(dartExecutable));
late final String frontendServerPath =
    path.join(sdkDir, 'bin', 'snapshots', 'frontend_server.dart.snapshot');

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stdout.writeln('> usage: fire path-to-dart-file [arguments].');
    exit(1);
  }

  var filePath = arguments[0];
  var fileUri = Uri.file(filePath);

  var output = path.setExtension(filePath, '.dill');
  arguments[0] = output;

  var client = await FrontendServerClient.start(filePath, output, kernel);

  var invalidated = <Uri>{};

  Future<void> watch(Set<Uri> invalidated, [Duration? pollingDelay]) {
    var watcher = Watcher('lib');

    watcher.events.listen((event) {
      stdout.writeln(event);
      invalidated.add(Uri.file(event.path));
    });

    return watcher.ready;
  }

  if (FileSystemEntity.isDirectorySync('lib')) {
    await watch(invalidated);
    stdout.writeln('> watching lib folder.');
  }

  Future<void> reload() async {
    try {
      var result = await client.compile(<Uri>[fileUri, ...invalidated]);
      invalidated.clear();

      if (result == null) {
        stdout.writeln('> no compilation result, rejecting.');
        return client.reject();
      }

      if (result.errorCount > 0) {
        stdout.writeln('> compiled with ${result.errorCount} error(s).');
        return client.reject();
      }

      for (var line in result.compilerOutputLines) {
        stdout.writeln(line);
      }

      client.accept();
      client.reset();
    } catch (error, trace) {
      stdout.writeln(error);
      stdout.writeln(Trace.format(trace));
    }
  }

  void run() {
    try {
      var result = Process.runSync(dartExecutable, arguments);

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

  var stopwatch = Stopwatch();

  stdout.write('> building...');
  stopwatch.start();
  await reload();
  stopwatch.stop();
  stdout.writeln('\r> building done, took ${stopwatch.elapsed}');
  stopwatch.reset();

  run();

  stdout.writeln('> press r to restart, q to exit.');

  stdin.echoMode = false;
  stdin.lineMode = false;

  await for (var bytes in stdin) {
    switch (bytes[0]) {
      case 114:
        stdout.write('> reloading...');
        stopwatch.start();
        await reload();
        stopwatch.stop();
        stdout.writeln('\r> reloading done, took ${stopwatch.elapsed}');
        stopwatch.reset();
        run();
        break;
      case 113:
        await client.shutdown().then<Never>(exit);
      default:
        var input = String.fromCharCodes(bytes);
        stdout.writeln('> expected r to reload and q to exit, got \'$input\'.');
    }
  }
}

// ignore_for_file: avoid_print
