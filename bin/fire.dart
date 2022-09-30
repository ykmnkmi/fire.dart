import 'dart:io' show FileSystemEntity, ProcessResult, exit, stdout;

import 'package:fire/fire.dart' show FireOutputDelegate, run_fire;
import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart' show Trace;

Future<void> main(
  final List<String> args,
) async {
  if (args.isEmpty) {
    print("> usage: fire file.dart [arguments].");
    exit(1);
  } else {
    final file_path = args[0];
    if (FileSystemEntity.isFileSync(file_path)) {
      await run_fire(
        file_path: file_path,
        output_path: path.setExtension(file_path, ".dill"),
        kernel_path: "lib/_internal/vm_platform_strong.dill",
        args: [
          if (args.isNotEmpty) ...args.sublist(1, args.length),
        ],
        output: _FireOutputDelegateImpl(
          output: stdout.writeln,
        ),
      );
    } else {
      print("'" + file_path + "' not found or isn't a file.");
      exit(2);
    }
  }
}

class _FireOutputDelegateImpl implements FireOutputDelegate {
  final void Function(String) output;

  const _FireOutputDelegateImpl({
    required this.output,
  });

  @override
  void output_error(
    final Object payload,
    final StackTrace stack_trace,
  ) {
    output(payload.toString());
    output(Trace.format(stack_trace));
  }

  @override
  void output_string(
    final String str,
  ) {
    output(str);
  }

  @override
  void output_compiler_output(
    final Iterable<String> values,
  ) {
    for (final line in values) {
      output(line);
    }
  }

  @override
  void redirect_process(
    final ProcessResult result,
  ) {
    // TODO https://stackoverflow.com/questions/33251129/what-is-the-best-way-to-stream-stdout-from-a-process-in-dart
    if (result.stdout != null) {
      output(result.stdout.toString().trimRight());
    }
    if (result.stderr != null) {
      output(result.stderr.toString().trimRight());
    }
  }
}
