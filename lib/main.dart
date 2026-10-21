import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const TvPlayerApp());
}

class TvPlayerApp extends StatelessWidget {
  const TvPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tvplayer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const PlayerScreen(),
    );
  }
}
