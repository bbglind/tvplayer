import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../shell/app_messages.dart';
import '../theme/app_colors.dart';
import 'settings_section.dart';

/// Settings › About: the app, and the credits its data sources ask for.
/// The TMDB logo stays smaller than the app's name, as TMDB's terms ask;
/// SkipDB's data is credited with its licence (ODbL), TheIntroDB with
/// its name and site.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const skipDbUrl = 'https://skipdb.tv';
  static const odblUrl = 'https://opendatacommons.org/licenses/odbl/1-0/';
  static const introDbUrl = 'https://theintrodb.org';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SettingsSection(
      title: 'About',
      children: [
        ListTile(
          leading: const Icon(Icons.live_tv),
          title: Text('tvplayer', style: text.titleLarge),
          subtitle: const Text(
            'A player for your own IPTV provider. It comes without '
            'playlists, channels or other content.',
          ),
        ),
        Padding(
          key: const Key('settings.about.tmdb'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Data sources', style: text.titleSmall),
              const SizedBox(height: 10),
              Image.asset(
                'assets/tmdb/tmdb_logo.png',
                key: const Key('settings.about.tmdbLogo'),
                height: 14,
                semanticLabel: 'TMDB',
              ),
              const SizedBox(height: 8),
              Text(
                'This product uses the TMDB API but is not endorsed or '
                'certified by TMDB.',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Intro, recap and credits times come from SkipDB and '
                'TheIntroDB, made by their communities.',
                key: const Key('settings.about.skip'),
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'SkipDB data © SkipDB contributors, available under the '
                'Open Database License (ODbL) 1.0.',
                key: const Key('settings.about.skipDb'),
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              const Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _Link(
                    key: Key('settings.about.skipDbLink'),
                    label: 'SkipDB',
                    url: skipDbUrl,
                  ),
                  _Link(
                    key: Key('settings.about.odblLink'),
                    label: 'ODbL 1.0',
                    url: odblUrl,
                  ),
                  _Link(
                    key: Key('settings.about.introDbLink'),
                    label: 'TheIntroDB',
                    url: introDbUrl,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A text button that opens [url] in the browser; the address is its
/// tooltip.
class _Link extends ConsumerWidget {
  const _Link({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Tooltip(
    message: url,
    child: TextButton.icon(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        if (!await ref.read(linkOpenerProvider)(Uri.parse(url))) {
          showAppMessage(
            messenger,
            "Couldn't open the browser. The address is $url",
            level: NoticeLevel.error,
          );
        }
      },
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(label),
    ),
  );
}
