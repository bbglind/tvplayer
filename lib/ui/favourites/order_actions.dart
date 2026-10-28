import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../shell/app_messages.dart';

/// "Move up", "Move down", "Move to top".
String moveStepLabel(MoveStep step) => switch (step) {
  MoveStep.up => 'Move up',
  MoveStep.down => 'Move down',
  MoveStep.top => 'Move to top',
};

IconData moveStepIcon(MoveStep step) => switch (step) {
  MoveStep.up => Icons.arrow_upward,
  MoveStep.down => Icons.arrow_downward,
  MoveStep.top => Icons.vertical_align_top,
};

/// Puts the provider categories of [kind] back in the provider's order and
/// offers "Undo" in a snack bar.
void resetCategoryOrderWithUndo(
  BuildContext context,
  WidgetRef ref,
  ContentKind kind,
) {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(favouritesProvider.notifier);
  final previous = notifier.resetOrder(kind);
  showAppMessage(
    messenger,
    'Categories are back in the provider’s order',
    key: const Key('categories.orderReset'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () => notifier.restoreOrder(kind, previous),
    ),
  );
}

/// "Reset to provider order" for the provider categories of [kind];
/// disabled while they are in the provider's order.
class ResetOrderButton extends ConsumerWidget {
  const ResetOrderButton({super.key, required this.kind});

  final ContentKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(
      favouritesProvider.select((f) => f.categoryOrder(kind) != null),
    );
    return Tooltip(
      message: 'Put the categories back in the provider’s order',
      child: TextButton(
        onPressed: custom
            ? () => resetCategoryOrderWithUndo(context, ref, kind)
            : null,
        child: const Text('Reset to provider order'),
      ),
    );
  }
}
