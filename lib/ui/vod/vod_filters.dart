import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';

/// Moves keyboard focus into a menu that just opened.
void _focusSoon(FocusNode node) =>
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.context != null) node.requestFocus();
    });

/// The label of [sort]; series say "Recently updated" (they are sorted by
/// their last update, not when they were added).
String sortLabel(VodSort sort, {required bool series}) => switch (sort) {
  VodSort.recent => series ? 'Recently updated' : 'Recently added',
  VodSort.title => 'A–Z',
  VodSort.rating => 'Top rated',
};

/// A check mark for the chosen entry of a menu, or the same space.
Widget _check(bool chosen) => chosen
    ? const Icon(Icons.check, size: 18, color: AppColors.accent)
    : const SizedBox(width: 18);

/// The sort chip of the Movies or Series tab and its menu.
class SortMenu extends StatefulWidget {
  const SortMenu({
    super.key,
    required this.section,
    required this.sort,
    required this.onChanged,
  });

  /// `movies` or `series`, for labels and widget keys.
  final String section;
  final VodSort sort;
  final ValueChanged<VodSort> onChanged;

  @override
  State<SortMenu> createState() => _SortMenuState();
}

class _SortMenuState extends State<SortMenu> {
  final _menu = MenuController();
  final _first = FocusNode(debugLabel: 'sort.menu.first');

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.section == 'series';
    return MenuAnchor(
      controller: _menu,
      onOpen: () => _focusSoon(_first),
      menuChildren: [
        for (final (i, sort) in VodSort.values.indexed)
          MenuItemButton(
            key: Key('${widget.section}.sort.${sort.name}'),
            focusNode: i == 0 ? _first : null,
            leadingIcon: _check(sort == widget.sort),
            onPressed: () => widget.onChanged(sort),
            child: Text(sortLabel(sort, series: series)),
          ),
      ],
      builder: (context, controller, _) => ToolbarChip(
        key: Key('${widget.section}.sort'),
        icon: Icons.sort,
        dropdown: true,
        tooltip: 'Sort',
        label: sortLabel(widget.sort, series: series),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The label of a year filter: "Year" when there is none.
String yearFilterLabel(YearFilter? filter) => switch (filter) {
  null => 'Year',
  YearFilter(years: 1) => 'This year',
  YearFilter(years: final n?) => 'Last $n years',
  YearFilter(from: final f?, to: final t?) when f == t => '$f',
  YearFilter(from: final f?, to: final t?) => '$f–$t',
  YearFilter(from: final f?) => 'From $f',
  YearFilter(to: final t?) => 'Until $t',
  _ => 'Year',
};

/// The year filter chip and its menu: quick picks and a custom range.
class YearFilterMenu extends StatefulWidget {
  const YearFilterMenu({
    super.key,
    required this.section,
    required this.filter,
    required this.onChanged,
  });

  /// `movies` or `series`, for widget keys.
  final String section;
  final YearFilter? filter;
  final ValueChanged<YearFilter?> onChanged;

  static const quickPicks = [
    YearFilter.recent(1),
    YearFilter.recent(2),
    YearFilter.recent(5),
  ];

  @override
  State<YearFilterMenu> createState() => _YearFilterMenuState();
}

class _YearFilterMenuState extends State<YearFilterMenu> {
  final _menu = MenuController();
  final _first = FocusNode(debugLabel: 'year.menu.first');

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  Future<void> _custom() async {
    final current = widget.filter;
    final range = await showDialog<YearFilter>(
      context: context,
      builder: (_) =>
          YearRangeDialog(initial: current?.years == null ? current : null),
    );
    if (range != null) widget.onChanged(range);
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final custom = filter != null && filter.years == null;
    final key = '${widget.section}.year';
    return MenuAnchor(
      controller: _menu,
      onOpen: () => _focusSoon(_first),
      menuChildren: [
        MenuItemButton(
          key: Key('$key.any'),
          focusNode: _first,
          leadingIcon: _check(filter == null),
          onPressed: () => widget.onChanged(null),
          child: const Text('Any year'),
        ),
        for (final pick in YearFilterMenu.quickPicks)
          MenuItemButton(
            key: Key('$key.${pick.years}'),
            leadingIcon: _check(filter == pick),
            onPressed: () => widget.onChanged(pick),
            child: Text(yearFilterLabel(pick)),
          ),
        MenuItemButton(
          key: Key('$key.custom'),
          leadingIcon: _check(custom),
          onPressed: _custom,
          child: Text(
            custom ? 'Custom: ${yearFilterLabel(filter)}…' : 'Custom range…',
          ),
        ),
      ],
      builder: (context, controller, _) => ToolbarChip(
        key: Key(key),
        icon: Icons.calendar_today_outlined,
        dropdown: true,
        selected: filter != null,
        tooltip: 'Release year',
        label: yearFilterLabel(filter),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Asks for a range of release years; either end may be left empty.
/// Returns the range, or null when cancelled.
class YearRangeDialog extends StatefulWidget {
  const YearRangeDialog({super.key, this.initial});

  final YearFilter? initial;

  @override
  State<YearRangeDialog> createState() => _YearRangeDialogState();
}

class _YearRangeDialogState extends State<YearRangeDialog> {
  late final _from = TextEditingController(
    text: widget.initial?.from?.toString() ?? '',
  );
  late final _to = TextEditingController(
    text: widget.initial?.to?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  static int? _year(String text) {
    final y = int.tryParse(text.trim());
    return y != null && y >= ParsedTitle.minYear && y <= ParsedTitle.maxYear
        ? y
        : null;
  }

  void _apply() {
    final fromText = _from.text.trim();
    final toText = _to.text.trim();
    final from = _year(fromText);
    final to = _year(toText);
    String? error;
    if ((fromText.isNotEmpty && from == null) ||
        (toText.isNotEmpty && to == null)) {
      error = 'Enter years like 1999 or 2024.';
    } else if (from == null && to == null) {
      error = 'Enter a first or a last year.';
    } else if (from != null && to != null && from > to) {
      error = 'The first year is after the last year.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(YearFilter.range(from: from, to: to));
  }

  Widget _field(String key, String label, TextEditingController c) => Expanded(
    child: TextField(
      key: Key(key),
      controller: c,
      autofocus: key == 'year.from',
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(labelText: label, hintText: 'Any'),
      onSubmitted: (_) => _apply(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Release years'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _field('year.from', 'From', _from),
                const SizedBox(width: 16),
                _field('year.to', 'To', _to),
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const Key('year.error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('year.apply'),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// The label of a genre filter: "Genre" when there is none.
String genreFilterLabel(Set<String> genres) => switch (genres.length) {
  0 => 'Genre',
  1 => genres.single,
  final n => '$n genres',
};

/// The genre filter chip and its menu: a checkbox per genre with how many
/// items have it. Stays open while ticking; Done, Esc or a click outside
/// closes it.
class GenreFilterMenu extends StatefulWidget {
  const GenreFilterMenu({
    super.key,
    required this.section,
    required this.genres,
    required this.selected,
    required this.onChanged,
  });

  /// `movies` or `series`, for widget keys.
  final String section;

  /// The genres to offer, with their counts.
  final List<({String genre, int count})> genres;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<GenreFilterMenu> createState() => _GenreFilterMenuState();
}

class _GenreFilterMenuState extends State<GenreFilterMenu> {
  final _menu = MenuController();
  final _first = FocusNode(debugLabel: 'genre.menu.first');

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  bool _isSelected(String genre) {
    final lower = genre.toLowerCase();
    return widget.selected.any((g) => g.toLowerCase() == lower);
  }

  void _toggle(String genre, bool on) {
    final lower = genre.toLowerCase();
    widget.onChanged({
      for (final g in widget.selected)
        if (g.toLowerCase() != lower) g,
      if (on) genre,
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = '${widget.section}.genre';
    final selected = widget.selected;
    // Selected genres no longer offered (e.g. after a refresh) stay
    // visible, so they can be unticked.
    final offered = {for (final g in widget.genres) g.genre.toLowerCase()};
    final entries = [
      ...widget.genres,
      for (final g in selected)
        if (!offered.contains(g.toLowerCase())) (genre: g, count: 0),
    ];
    return MenuAnchor(
      controller: _menu,
      onOpen: () => _focusSoon(_first),
      menuChildren: [
        if (entries.isEmpty)
          const MenuItemButton(child: Text('No genres'))
        else
          for (final (i, g) in entries.indexed)
            CheckboxMenuButton(
              key: Key('$key.${g.genre}'),
              focusNode: i == 0 ? _first : null,
              value: _isSelected(g.genre),
              closeOnActivate: false,
              onChanged: (v) => _toggle(g.genre, v ?? false),
              trailingIcon: Text(
                formatCount(g.count),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              child: Text(g.genre),
            ),
        const Divider(height: 9),
        MenuItemButton(
          key: Key('$key.clear'),
          leadingIcon: const Icon(Icons.clear_all),
          onPressed: selected.isEmpty ? null : () => widget.onChanged(const {}),
          child: const Text('Clear genres'),
        ),
        MenuItemButton(
          key: Key('$key.done'),
          leadingIcon: const Icon(Icons.check),
          focusNode: entries.isEmpty ? _first : null,
          onPressed: _menu.close,
          child: const Text('Done'),
        ),
      ],
      builder: (context, controller, _) => ToolbarChip(
        key: Key(key),
        icon: Icons.theater_comedy_outlined,
        dropdown: true,
        selected: selected.isNotEmpty,
        tooltip: 'Genre',
        label: genreFilterLabel(selected),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
