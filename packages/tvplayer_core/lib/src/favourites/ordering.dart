/// The moves of the Move up, Move down and Move to top menu entries.
enum MoveStep { up, down, top }

/// Where [step] moves [id] in [ids], as the index to move it to (the
/// `toIndex` of the move functions); null when it can't move that way,
/// so the menu entry is disabled.
///
/// Up and down pass over the [skip]ped entries, the ones the user doesn't
/// see (hidden categories, items left out by a search), so one step always
/// moves past a visible neighbour. To top is null when no visible entry is
/// above.
int? moveTarget(
  List<String> ids,
  String id,
  MoveStep step, {
  Set<String> skip = const {},
}) {
  final from = ids.indexOf(id);
  if (from < 0) return null;
  int? visible(Iterable<int> indexes) {
    for (final i in indexes) {
      if (!skip.contains(ids[i])) return i;
    }
    return null;
  }

  final above = visible([for (var i = from - 1; i >= 0; i--) i]);
  return switch (step) {
    MoveStep.up => above,
    MoveStep.top => above == null ? null : 0,
    // Taken out first, it lands after the neighbour at that index.
    MoveStep.down => visible([for (var i = from + 1; i < ids.length; i++) i]),
  };
}
