import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/provider_storage.dart';
import 'state/providers.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/shell/app_shell.dart';

class TvPlayerApp extends ConsumerStatefulWidget {
  const TvPlayerApp({super.key});

  @override
  ConsumerState<TvPlayerApp> createState() => _TvPlayerAppState();
}

class _TvPlayerAppState extends ConsumerState<TvPlayerApp> {
  // Closing the window must not leave an external mpv running.
  late final _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await ref.read(externalMpvProvider).stop();
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
      home: const RootGate(),
    );
  }
}

/// Shows setup when no provider is saved, Live TV otherwise, and a keyring
/// error with retry when the saved provider can't be read.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(savedProviderProvider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => _StorageErrorScreen(
            message: error is ProviderStorageException
                ? error.message
                : 'Could not load the saved provider (${error.runtimeType}).',
            onRetry: () => ref.invalidate(savedProviderProvider),
          ),
          data: (config) =>
              config == null ? const SetupScreen() : const AppShell(),
        );
  }
}

class _StorageErrorScreen extends StatelessWidget {
  const _StorageErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.key_off,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Keyring unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
