import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// `Svenska (Swedish)`, or just `English`.
String languageName(Language language) =>
    language.nativeName == language.englishName
    ? language.englishName
    : '${language.nativeName} (${language.englishName})';

/// The languages of [codes] by name, e.g. `Svenska, English`, or [empty].
String describeLanguages(List<String> codes, {required String empty}) {
  final names = [
    for (final code in codes)
      if (Language.parse(code) case final l?) l.nativeName,
  ];
  return names.isEmpty ? empty : names.join(', ');
}

/// Lets the user order, add and remove preferred languages. Returns the new
/// list of ISO 639-1 codes, or null when cancelled.
Future<List<String>?> showLanguageListEditor(
  BuildContext context, {
  required String title,
  required List<String> initial,
  String? emptyHint,
}) => showDialog<List<String>>(
  context: context,
  builder: (context) =>
      _LanguageListDialog(title: title, initial: initial, emptyHint: emptyHint),
);

class _LanguageListDialog extends StatefulWidget {
  const _LanguageListDialog({
    required this.title,
    required this.initial,
    this.emptyHint,
  });

  final String title;
  final List<String> initial;
  final String? emptyHint;

  @override
  State<_LanguageListDialog> createState() => _LanguageListDialogState();
}

class _LanguageListDialogState extends State<_LanguageListDialog> {
  late final List<Language> _chosen = [
    for (final code in widget.initial) ?Language.parse(code),
  ];

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final l in Language.all)
        if (!_chosen.contains(l)) l,
    ]..sort((a, b) => a.englishName.compareTo(b.englishName));
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The first language available is used. Drag to reorder.',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _chosen.isEmpty
                  ? Center(child: Text(widget.emptyHint ?? 'No languages'))
                  : ReorderableListView(
                      buildDefaultDragHandles: false,
                      onReorderItem: (from, to) => setState(
                        () => _chosen.insert(to, _chosen.removeAt(from)),
                      ),
                      children: [
                        for (final (i, l) in _chosen.indexed)
                          ListTile(
                            key: ValueKey(l.code),
                            leading: ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle),
                            ),
                            title: Text('${i + 1}. ${languageName(l)}'),
                            trailing: IconButton(
                              tooltip: 'Remove ${l.englishName}',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _chosen.remove(l)),
                            ),
                          ),
                      ],
                    ),
            ),
            PopupMenuButton<Language>(
              key: const Key('languages.add'),
              tooltip: 'Add a language',
              onSelected: (l) => setState(() => _chosen.add(l)),
              itemBuilder: (context) => [
                for (final l in available)
                  PopupMenuItem(value: l, child: Text(languageName(l))),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add),
                    SizedBox(width: 8),
                    Text('Add language'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, [for (final l in _chosen) l.code]),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
