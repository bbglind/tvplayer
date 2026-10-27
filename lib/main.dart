import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/legacy_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything reads or creates files in the data folders.
  await migrateLegacyData();
  MediaKit.ensureInitialized();
  // No automatic retries: failures surface immediately with a retry button.
  runApp(ProviderScope(retry: (_, _) => null, child: const TvPlayerApp()));
}
