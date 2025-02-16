import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    return;
  }

  for (int i = 0; i < arguments.length; i++) {
    String filePath = arguments[i];
    File file = File(filePath);

    if (file.existsSync()) {
      stdout.write(file.readAsStringSync());
    } else {
      stderr.writeln('cat: $filePath: No such file or directory');
    }
  }
}
