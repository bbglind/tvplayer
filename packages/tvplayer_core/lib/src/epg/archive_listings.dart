import '../live/live_source.dart';
import '../models/epg_program.dart';
import 'epg_guide.dart';

/// [guide]'s programmes of one channel plus those of the provider's
/// [archive] listing that don't overlap any of them, sorted by start.
///
/// The XMLTV guide stays the source wherever it has programmes; the archive
/// listing (which reaches further back) only fills in before them and in
/// gaps. Archive programmes sharing a start are kept once.
List<EpgProgram> mergeArchive(
  List<EpgProgram> guide,
  List<EpgProgram> archive,
) {
  if (archive.isEmpty) return guide;
  final added = <EpgProgram>[];
  final sorted = [...archive]..sort((a, b) => a.start.compareTo(b.start));
  for (final p in sorted) {
    if (!p.stop.isAfter(p.start)) continue;
    if (added.isNotEmpty && p.start.isBefore(added.last.stop)) continue;
    final i = EpgGuide.firstEndingAfter(guide, p.start);
    if (i < guide.length && guide[i].start.isBefore(p.stop)) continue;
    added.add(p);
  }
  if (added.isEmpty) return guide;
  return List.unmodifiable(
    [...guide, ...added]..sort((a, b) => a.start.compareTo(b.start)),
  );
}

/// Looks up a channel's programmes in the XMLTV [guide] together with the
/// provider's archive listings ([archive], by [LiveStream.id]), merged with
/// [mergeArchive].
final class GuideLookup {
  GuideLookup(this.guide, [this.archive = const {}]);

  final EpgGuide guide;
  final Map<String, List<EpgProgram>> archive;

  final Map<String, List<EpgProgram>> _merged = {};

  /// All programmes of [channel], sorted by start.
  List<EpgProgram> programsFor(LiveStream channel) {
    final past = archive[channel.id];
    if (past == null || past.isEmpty) return guide.programsFor(channel);
    return _merged.putIfAbsent(
      channel.id,
      () => mergeArchive(guide.programsFor(channel), past),
    );
  }

  /// Programmes of [channel] that overlap `[from, to)`.
  List<EpgProgram> between(LiveStream channel, DateTime from, DateTime to) =>
      EpgGuide.overlapping(programsFor(channel), from, to);

  /// The programme of [channel] airing at [at] and the next one.
  NowNext nowAndNext(LiveStream channel, DateTime at) =>
      EpgGuide.nowAndNextIn(programsFor(channel), at);

  /// The start of [channel]'s first XMLTV programme; null when the guide
  /// has none. Before it only the archive listing can say what aired.
  DateTime? guideStart(LiveStream channel) =>
      guide.programsFor(channel).firstOrNull?.start;
}
