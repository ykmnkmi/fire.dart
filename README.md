[![Pub Package](https://img.shields.io/pub/v/fire.svg)](https://pub.dev/packages/fire)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Hot restart for console application.

## Why I need this?

If your console application compiles too long before running. And `dart run`, which is now supports incremental compilation, seems too slow.

## Install

Use the dart pub global command to install this into your system.

```console
$ dart pub global activate fire
```

## Use

If you have [modified your PATH][path], you can run this from any local directory.

```console
$ fire
```

Otherwise you can use the `dart pub global` command.

```console
$ dart pub global run fire
```

Here's an example of running a console application:

```console
$ fire bin/cat.dart example/example.dart
> watching 'lib' folder.
> building done, took 0:00:00.000054
void main() {
  print('hello cat!');
}

> press r to restart, q to exit.
```

While running creates `bin/cat.dill` incremental kernel snapshot.

## ToDo

* Option to change arguments
* Builders support
* AOT compilation, [it's impossible for now](https://github.com/dart-lang/sdk/issues/47322)

## Alternatives

* https://pub.dev/packages/angel3_hot
* https://pub.dev/packages/jaguar_hotreload
* https://pub.dev/packages/hotreloader
* https://pub.dev/packages/recharge
* https://pub.dev/packages/reloader

## Related

* https://pub.dev/packages/frontend_server_client
* https://pub.dev/packages/build_vm_compilers

[path]: https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path