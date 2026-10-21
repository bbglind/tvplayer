import 'dart:io';

/// Reads a file from test/fixtures. Tests run from the package root.
String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

Stream<List<int>> fixtureBytes(String path) =>
    File('test/fixtures/$path').openRead();
