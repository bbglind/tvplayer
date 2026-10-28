import 'package:flutter/material.dart';

import '../../state/notice_level.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

export '../../state/notice_level.dart';

/// How long every message stays.
const messageDuration = Duration(seconds: 6);

/// Shows [text] in a snack bar, the only way the app shows a message.
/// It replaces the current one, closes by itself after [messageDuration]
/// (also with an [action]) and when another page opens. Errors and
/// warnings get a `live` bar and icon, successes a `success` bar and
/// check; info looks plain.
void showAppMessage(
  ScaffoldMessengerState messenger,
  String text, {
  NoticeLevel level = NoticeLevel.info,
  Key? key,
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: key,
        duration: messageDuration,
        // With an action a snack bar stays until dismissed by default.
        persist: false,
        content: AppMessageContent(text, level: level),
        action: action,
      ),
    );
}

/// The text of a message, after its level's bar and icon.
class AppMessageContent extends StatelessWidget {
  const AppMessageContent(this.text, {super.key, required this.level});

  final String text;
  final NoticeLevel level;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (level) {
      NoticeLevel.info => (null, null),
      NoticeLevel.success => (AppColors.success, Icons.check_circle_outline),
      NoticeLevel.warning => (AppColors.live, Icons.warning_amber_rounded),
      NoticeLevel.error => (AppColors.live, Icons.error_outline),
    };
    if (color == null || icon == null) return Text(text);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('message.bar'),
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Align(
            alignment: Alignment.topCenter,
            child: Icon(
              icon,
              key: Key('message.icon.${level.name}'),
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: Text(text)),
          ),
        ],
      ),
    );
  }
}
