import 'package:flutter/material.dart';

/// Icons to choose from for my categories, by the key stored with the
/// category ([FavouriteCategory.icon]). Keys must stay the same once used.
const categoryIcons = <String, IconData>{
  'star': Icons.star_outline,
  'heart': Icons.favorite_outline,
  'sport': Icons.sports_outlined,
  'soccer': Icons.sports_soccer_outlined,
  'news': Icons.newspaper_outlined,
  'movie': Icons.movie_outlined,
  'tv': Icons.live_tv_outlined,
  'series': Icons.video_library_outlined,
  'kids': Icons.child_care_outlined,
  'family': Icons.family_restroom_outlined,
  'music': Icons.music_note_outlined,
  'documentary': Icons.forest_outlined,
  'history': Icons.history_edu_outlined,
  'science': Icons.science_outlined,
  'comedy': Icons.sentiment_very_satisfied_outlined,
  'drama': Icons.theater_comedy_outlined,
  'crime': Icons.local_police_outlined,
  'travel': Icons.flight_outlined,
  'food': Icons.restaurant_outlined,
  'gaming': Icons.sports_esports_outlined,
  'night': Icons.bedtime_outlined,
};

const defaultCategoryIcon = 'star';

/// The icon for [key]; the star for unknown keys (e.g. from a newer
/// version on another device).
IconData categoryIcon(String key) =>
    categoryIcons[key] ?? categoryIcons[defaultCategoryIcon]!;
