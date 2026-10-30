import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/default_categories.dart';
import 'data/legacy_data.dart';
import 'data/videos_directory.dart';
import 'player/touch/device_controls.dart';
import 'state/providers.dart';
import 'state/downloads_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything reads or creates files in the data folders.
  await migrateLegacyData();
  await FileDefaultCategoriesStore().prepare();
  // The Linux default is found synchronously; Android's needs a plugin.
  final downloadFolder = Platform.isAndroid
      ? await androidDownloadFolder()
      : null;
  MediaKit.ensureInitialized();
  // Phones browse in portrait; the player turns to landscape by itself.
  final device = Platform.isAndroid
      ? AndroidDeviceControls(
          portraitOnly: AndroidDeviceControls.isPhone(
            WidgetsBinding.instance.platformDispatcher.views.first,
          ),
        )
      : null;
  await device?.lockPortrait();
  // No automatic retries: failures surface immediately with a retry button.
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        if (downloadFolder != null)
          defaultDownloadFolderProvider.overrideWithValue(downloadFolder),
        if (device != null) deviceControlsProvider.overrideWithValue(device),
      ],
      child: const TvPlayerApp(),
    ),
  );
}
