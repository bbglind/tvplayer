import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/legacy_data.dart';
import 'data/videos_directory.dart';
import 'state/downloads_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything reads or creates files in the data folders.
  await migrateLegacyData();
  // The Linux default is found synchronously; Android's needs a plugin.
  final downloadFolder = Platform.isAndroid
      ? await androidDownloadFolder()
      : null;
  MediaKit.ensureInitialized();
  // No automatic retries: failures surface immediately with a retry button.
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        if (downloadFolder != null)
          defaultDownloadFolderProvider.overrideWithValue(downloadFolder),
      ],
      child: const TvPlayerApp(),
    ),
  );
}
