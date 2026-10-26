import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../player/player_hint.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';

/// The provider's own tag of a title (`NF-DO`, `4K-SC`), shown as-is: we
/// don't know what the abbreviations mean.
class ProviderLabel extends StatelessWidget {
  const ProviderLabel(this.label, {super.key, this.large = false});

  final String label;

  /// For page and hero titles.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 13.0 : 11.0;
    return Container(
      key: const Key('provider.label'),
      padding: EdgeInsets.symmetric(horizontal: large ? 6 : 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: size * 0.08,
          height: 1.25,
        ),
      ),
    );
  }
}

/// A movie, series or episode title from the provider's [name]: without
/// the provider's tag, year and country, with the tag as a [ProviderLabel]
/// in front. Hovering it (or keyboard focus on the item around it) shows
/// the full [name] when something was hidden or cut off.
///
/// [title] replaces the shown text, e.g. an episode's own name; the label
/// still comes from [name]. [fullName] replaces the tooltip.
class ProviderTitle extends ConsumerWidget {
  const ProviderTitle(
    this.name, {
    super.key,
    this.title,
    this.style,
    this.maxLines = 1,
    this.large = false,
    this.fullName,
    this.player = false,
    this.textKey,
  });

  final String name;
  final String? title;
  final TextStyle? style;
  final int maxLines;
  final bool large;
  final String? fullName;

  /// In the player: the full name shows in the hint line, since tooltips
  /// can't be drawn over the video (Player hints rule).
  final bool player;
  final Key? textKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(providerTagsProvider).display(name);
    final shown = title ?? display.title;
    final label = display.label;
    final leading = label == null
        ? null
        : WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: large ? 10 : 6),
              child: ProviderLabel(label, large: large),
            ),
          );
    final full =
        fullName ?? (display.shortened || shown != display.title ? name : null);
    if (player) {
      final text = Text.rich(
        TextSpan(
          children: [
            ?leading,
            TextSpan(text: shown),
          ],
        ),
        key: textKey,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
      return full == null ? text : PlayerTooltip(message: full, child: text);
    }
    return TruncatedText(
      shown,
      key: textKey,
      style: style,
      maxLines: maxLines,
      leading: leading,
      tooltip: full,
    );
  }
}

/// [name] as plain text: without the provider's tag, year and country.
String plainTitle(WidgetRef ref, String name) =>
    ref.read(providerTagsProvider).display(name).title;
