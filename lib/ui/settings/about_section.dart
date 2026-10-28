import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'settings_section.dart';

/// Settings › About: the app, and the credits its data sources ask for.
/// The TMDB logo stays smaller than the app's name, as TMDB's terms ask.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

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
            ],
          ),
        ),
      ],
    );
  }
}
