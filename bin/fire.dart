import 'dart:io' show FileSystemEntity, Platform, Process, exit, stdin, stdout;

import 'package:frontend_server_client/frontend_server_client.dart'
    show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:watcher/watcher.dart' show Watcher;

const String kernel = 'lib/_internal/vm_platform_strong.dill';

late final String dartExecutable = path.normalize(Platform.resolvedExecutable);
late final String sdkDir = path.dirname(path.dirname(dartExecutable));

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stdout.writeln('> usage: fire file.dart [arguments].');
    exit(1);
  }

  var filePath = arguments[0];
  var fileUri = path.toUri(filePath);

  if (!FileSystemEntity.isFileSync(filePath)) {
    stdout.writeln('\'$filePath\' not found or is\'n a file.');
    exit(2);
  }

  var output = path.setExtension(filePath, '.dill');
  arguments[0] = output;

  FrontendServerClient client;

  try {
    client = await FrontendServerClient.start(filePath, output, kernel);
  } catch (error, stackTrace) {
    stdout.writeln(error);
    stdout.writeln(Trace.format(stackTrace));
    exit(3);
  }

  var invalidated = <Uri>{};

  Future<void> watch(Set<Uri> invalidated) {
    var watcher = Watcher('lib');

    watcher.events.listen((event) {
      stdout.writeln(event);
      invalidated.add(path.toUri(event.path));
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
        stdout.writeln();
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

  Future<void> run() async {
    try {
      var result = await Process.run(dartExecutable, arguments);

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
  stdout.write('> compiling...');
  stopwatch.start();
  await reload();
  stopwatch.stop();
  stdout.writeln('\r> compiling done, took ${stopwatch.elapsed}');
  stopwatch.reset();
  await run();
  stdout.writeln('> press r to restart and q to exit.');

  stdin.echoMode = false;
  stdin.lineMode = false;

  await for (var bytes in stdin) {
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
        var exitCode = await client.shutdown();
        exit(exitCode);
      default:
        var input = String.fromCharCodes(bytes);
        stdout.writeln('> expected r to restart and q to exit, got \'$input\'.');
    }
  }
}

// ignore_for_file: avoid_print
