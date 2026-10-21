import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/connection_tester.dart';
import '../data/provider_storage.dart';
import 'providers.dart';

/// State of the provider setup form (everything except the field values).
final class SetupState {
  const SetupState({
    this.testing = false,
    this.saving = false,
    this.result,
    this.saveError,
  });

  final bool testing;
  final bool saving;

  /// Last connection test result; cleared when the form changes.
  final ConnectionResult? result;
  final String? saveError;

  bool get busy => testing || saving;
}

final setupControllerProvider =
    NotifierProvider.autoDispose<SetupController, SetupState>(
      SetupController.new,
    );

class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  /// Clears a stale test result after the user edits the form.
  void formChanged() {
    if (state.result != null || state.saveError != null) {
      state = const SetupState();
    }
  }

  Future<void> testConnection(ProviderConfig config) async {
    state = const SetupState(testing: true);
    final result = await ref.read(connectionTesterProvider).test(config);
    if (ref.mounted) state = SetupState(result: result);
  }

  /// Saves [config]; returns whether it succeeded.
  Future<bool> save(ProviderConfig config) async {
    state = SetupState(saving: true, result: state.result);
    try {
      await ref.read(savedProviderProvider.notifier).save(config);
      if (ref.mounted) state = SetupState(result: state.result);
      return true;
    } on ProviderStorageException catch (e) {
      if (ref.mounted) {
        state = SetupState(result: state.result, saveError: e.message);
      }
      return false;
    }
  }
}
