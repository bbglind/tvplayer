import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../data/errors.dart';
import '../../format.dart';
import '../../state/category_selection.dart';
import '../../state/guide_controller.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import '../favourites/category_icons.dart';
import '../live/separator_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../player/open_channel.dart';

/// The full TV guide: channels down the side, time across the top.
class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guideState = ref.watch(guideProvider);
    final catalog = ref.watch(liveCatalogProvider);
    if (!guideState.supported) {
      return const _Message(
        icon: Icons.event_busy,
        title: 'No TV guide',
        text: 'The TV guide is only available for Xtream providers.',
      );
    }
    final guide = guideState.guide;
    if (guide == null) {
      if (guideState.error case final error? when !guideState.loading) {
        return _Message(
          icon: Icons.error_outline,
          title: 'Could not load the TV guide',
          text: error,
          onRetry: () => refreshPlaylistPart(ref, PlaylistPart.guide),
        );
      }
      return const _Message(
        title: 'Loading the TV guide…',
        text: 'The first download can take a while for large guides.',
        loading: true,
      );
    }
    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(
        icon: Icons.error_outline,
        title: 'Could not load channels',
        text: describeRefreshError(error),
        onRetry: () => refreshPlaylistPart(ref, PlaylistPart.channels),
      ),
      data: (catalog) {
        final channels = ref.watch(categoryChannelsProvider).value ?? const [];
        return Column(
          children: [
            _Toolbar(catalog: catalog, state: guideState),
            if (guideState.loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(
              child: channels.isEmpty
                  ? const Center(child: Text('No channels'))
                  : GuideGrid(channels: channels, guide: guide),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.catalog, required this.state});

  final LiveCatalog catalog;
  final GuideState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = ref.watch(guideTimeProvider);
    final selected = ref.watch(liveSelectionProvider);
    final favourites = ref.watch(favouritesProvider);
    final hidden = favourites.hiddenIds(ContentKind.live);
    final guide = state.guide;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 20, 12),
      child: Row(
        children: [
          Flexible(
            child: DropdownButton<CategorySelection>(
              key: const Key('guide.category'),
              value: selected,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.small),
              focusColor: AppColors.hover,
              style: Theme.of(context).textTheme.titleMedium,
              items: [
                for (final c in favourites.categoriesOf(ContentKind.live))
                  DropdownMenuItem(
                    value: MyCategory(c.id),
                    child: Row(
                      children: [
                        Icon(categoryIcon(c.icon), size: 18),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                const DropdownMenuItem(
                  value: AllCategories(),
                  child: Text('All channels'),
                ),
                for (final c in catalog.categories)
                  if (!hidden.contains(c.id))
                    DropdownMenuItem(
                      value: ProviderCategory(c.id),
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: (s) {
                if (s != null) {
                  ref.read(selectedCategoryProvider.notifier).select(s);
                }
              },
            ),
          ),
          const Spacer(),
          if (state.error case final error?)
            Tooltip(
              message: 'Last update failed: $error',
              child: Icon(
                Icons.warning_amber,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          const SizedBox(width: 8),
          if (guide != null)
            Flexible(
              child: TruncatedText(
                'Updated ${formatGuideDate(time, guide.fetchedAt)} '
                '${time.formatLocalHm(guide.fetchedAt)} · ${time.zoneName}'
                '${time.shiftHours == 0 ? '' : ' (${formatShift(time.shiftHours)})'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          IconButton(
            tooltip: 'Refresh TV guide',
            icon: const Icon(Icons.refresh),
            onPressed: state.loading
                ? null
                : () => refreshPlaylistPart(ref, PlaylistPart.guide),
          ),
        ],
      ),
    );
  }
}

/// `+2 h` / `-1 h`.
String formatShift(int hours) => '${hours > 0 ? '+' : ''}$hours h';

/// `Sun 25 Oct` for the real moment [time] in the display zone.
String formatGuideDate(GuideTime time, DateTime moment) {
  final l = time.local(moment);
  return '${weekdayNames[l.weekday - 1]} ${l.day} ${monthNames[l.month - 1]}';
}

class _Message extends StatelessWidget {
  const _Message({
    this.icon,
    required this.title,
    required this.text,
    this.onRetry,
    this.loading = false,
  });

  final IconData? icon;
  final String title;
  final String text;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const CircularProgressIndicator()
          else if (icon != null)
            Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The guide grid. The channel column stays put when scrolling sideways and
/// the time row stays put when scrolling up and down: each is its own
/// scroll view, kept in step with the programme area.
///
/// Moving through time: drag, the scrollbar under the programmes, a
/// sideways touchpad swipe or Shift + mouse wheel, anywhere on the grid.
/// The channel column's right edge can be dragged to resize it.
class GuideGrid extends ConsumerStatefulWidget {
  const GuideGrid({super.key, required this.channels, required this.guide});

  final List<LiveStream> channels;
  final EpgGuide guide;

  static const pixelsPerMinute = 4.0;

  /// Room under the last row for the horizontal scrollbar.
  static const scrollbarSpace = 16.0;

  static double _line(BuildContext context, TextStyle? style) =>
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
      (style?.height ?? 1.3);

  /// Height of a row. Grows with the text scale, so a programme's title
  /// and time, and a two-line channel name, always fit.
  static double rowHeight(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final program =
        _line(context, text.titleSmall) +
        _line(context, text.bodySmall) +
        _ProgramCell.margin.vertical +
        _ProgramCell.padding.vertical;
    final channel = 2 * _line(context, text.bodyMedium) + 4;
    return math.max(56.0, math.max(program, channel)).ceilToDouble();
  }

  /// Height of the time row; grows with the text scale like [rowHeight].
  static double headerHeight(BuildContext context) => math
      .max(40.0, _line(context, Theme.of(context).textTheme.titleSmall) + 14)
      .ceilToDouble();

  /// How far back the grid starts, before the current hour.
  static const past = Duration(hours: 2);

  /// The grid shows at least this much, and at most [maxSpan].
  static const minSpan = Duration(hours: 24);
  static const maxSpan = Duration(days: 8);

  @override
  ConsumerState<GuideGrid> createState() => GuideGridState();
}

class GuideGridState extends ConsumerState<GuideGrid> {
  /// Programmes are built for a window around the visible area; the window
  /// moves in steps of this many minutes of scrolling.
  static const _stepMinutes = 120;

  late final DateTime _opened = ref.read(clockProvider);
  late final ScrollController _bodyH;
  late final ScrollController _headerH;
  final _bodyV = ScrollController();
  final _channelsV = ScrollController();
  int _step = 0;

  /// The width the user is dragging the channel column to; null when not
  /// dragging.
  double? _dragWidth;

  static const _px = GuideGrid.pixelsPerMinute;

  /// Start of the grid (a UTC instant on a display-zone hour).
  DateTime _start(GuideTime time) =>
      time.startOfHour(_opened.subtract(GuideGrid.past));

  double _x(DateTime start, DateTime moment) =>
      moment.difference(start).inSeconds / 60 * _px;

  @override
  void initState() {
    super.initState();
    final start = _start(ref.read(guideTimeProvider));
    final initial = math.max(0.0, _x(start, _opened) - 30 * _px);
    _bodyH = ScrollController(initialScrollOffset: initial);
    _headerH = ScrollController(initialScrollOffset: initial);
    _step = _stepOf(initial);
    _bodyV.addListener(() => _sync(_bodyV, _channelsV));
    _channelsV.addListener(() => _sync(_channelsV, _bodyV));
    _bodyH.addListener(_onHorizontal);
  }

  int _stepOf(double offset) => offset ~/ (_stepMinutes * _px);

  static void _sync(ScrollController from, ScrollController to) {
    if (!from.hasClients || !to.hasClients) return;
    if (to.offset != from.offset) to.jumpTo(from.offset);
  }

  void _onHorizontal() {
    _sync(_bodyH, _headerH);
    final step = _stepOf(_bodyH.offset);
    if (step != _step) setState(() => _step = step);
  }

  /// Moves through time by [dx] pixels, within the grid.
  void _scrollTimeBy(double dx) {
    if (!_bodyH.hasClients || dx == 0) return;
    final p = _bodyH.position;
    final target = (p.pixels + dx).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (target != p.pixels) _bodyH.jumpTo(target);
  }

  /// Shift + wheel and sideways wheel/touchpad scrolls move through time.
  /// Rows handle these themselves, ahead of the scroll views (which would
  /// flip a Shift scroll that the platform already turned sideways back to
  /// vertical); everything else is left to the scroll views.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final d = event.scrollDelta;
    final double dx;
    if (HardwareKeyboard.instance.isShiftPressed) {
      dx = d.dx != 0 ? d.dx : d.dy;
    } else if (d.dx.abs() > d.dy.abs()) {
      dx = d.dx;
    } else {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _scrollTimeBy(dx),
    );
  }

  /// Takes scroll signals for [child] before the scroll views around it.
  Widget _signals(Widget child) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerSignal: _onPointerSignal,
    child: child,
  );

  /// A sideways touchpad swipe over [child] (the channel column or the time
  /// row) moves through time, as it does over the programmes.
  Widget _swipeTime(Widget child) => GestureDetector(
    supportedDevices: const {
      PointerDeviceKind.trackpad,
      PointerDeviceKind.touch,
    },
    onHorizontalDragUpdate: (d) => _scrollTimeBy(-d.delta.dx),
    child: child,
  );

  void _endDrag() {
    final width = _dragWidth;
    if (width == null) return;
    setState(() => _dragWidth = null);
    ref
        .read(appSettingsProvider.notifier)
        .remember((s) => s.copyWith(guideChannelWidth: _clampWidth(width)));
  }

  static double _clampWidth(double width) => width.clamp(
    AppSettings.minGuideChannelWidth,
    AppSettings.maxGuideChannelWidth,
  );

  /// Scrolls so the current time is near the left edge.
  void scrollToNow() {
    final start = _start(ref.read(guideTimeProvider));
    final now = ref.read(clockProvider);
    final target = (_x(start, now) - 30 * _px).clamp(
      0.0,
      _bodyH.position.maxScrollExtent,
    );
    _bodyH.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _bodyH.dispose();
    _headerH.dispose();
    _bodyV.dispose();
    _channelsV.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = ref.watch(guideTimeProvider);
    final now = ref.watch(clockProvider);
    final start = _start(time);
    var span = GuideGrid.minSpan;
    if (widget.guide.end case final end?) {
      final guideSpan = time.adjust(end).difference(start);
      if (guideSpan > span) span = guideSpan;
    }
    if (span > GuideGrid.maxSpan) span = GuideGrid.maxSpan;
    final width = span.inMinutes * _px;
    final channelWidth = _clampWidth(
      _dragWidth ??
          ref.watch(appSettingsProvider).value?.guideChannelWidth ??
          AppSettings.defaultGuideChannelWidth,
    );
    final rowHeight = GuideGrid.rowHeight(context);
    final headerHeight = GuideGrid.headerHeight(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleMinutes = (constraints.maxWidth - channelWidth) / _px;
        final from = start.add(Duration(minutes: (_step - 1) * _stepMinutes));
        final to = from.add(
          Duration(minutes: visibleMinutes.ceil() + 3 * _stepMinutes),
        );
        final window = (from: from, to: to);
        final behavior = ScrollConfiguration.of(context)
            .copyWith(dragDevices: PointerDeviceKind.values.toSet());
        final grid = Column(
          children: [
            SizedBox(
              height: headerHeight,
              child: Row(
                children: [
                  _Corner(
                    controller: _bodyH,
                    time: time,
                    start: start,
                    width: channelWidth + 1,
                    onNow: scrollToNow,
                  ),
                  Expanded(
                    child: _swipeTime(
                      SingleChildScrollView(
                        key: const Key('guide.header'),
                        controller: _headerH,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: _TimeHeader(
                          time: time,
                          start: start,
                          width: width,
                          height: headerHeight,
                          window: window,
                          nowX: _x(start, now),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: channelWidth,
                    child: _swipeTime(
                      ListView.builder(
                        key: const Key('guide.channels'),
                        controller: _channelsV,
                        padding: const EdgeInsets.only(
                          bottom: GuideGrid.scrollbarSpace,
                        ),
                        itemExtent: rowHeight,
                        itemCount: widget.channels.length,
                        itemBuilder: (context, i) => _signals(
                          widget.channels[i].isSeparator
                              ? SeparatorHeader(channel: widget.channels[i])
                              : _ChannelCell(channel: widget.channels[i]),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ScrollbarTheme(
                      data: ScrollbarTheme.of(
                        context,
                      ).copyWith(thickness: const WidgetStatePropertyAll(10)),
                      child: Scrollbar(
                        key: const Key('guide.scrollbar'),
                        controller: _bodyH,
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        child: ScrollConfiguration(
                          // The scrollbar above replaces the default ones.
                          behavior: behavior.copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            key: const Key('guide.body'),
                            controller: _bodyH,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: width,
                              child: Stack(
                                children: [
                                  ListView.builder(
                                    key: const Key('guide.rows'),
                                    controller: _bodyV,
                                    padding: const EdgeInsets.only(
                                      bottom: GuideGrid.scrollbarSpace,
                                    ),
                                    itemExtent: rowHeight,
                                    itemCount: widget.channels.length,
                                    itemBuilder: (context, i) => _signals(
                                      widget.channels[i].isSeparator
                                          ? const ColoredBox(
                                              color: AppColors.surface,
                                            )
                                          : _GuideRow(
                                              channel: widget.channels[i],
                                              guide: widget.guide,
                                              time: time,
                                              start: start,
                                              window: window,
                                              now: now,
                                              width: width,
                                              scroll: _bodyH,
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    key: const Key('guide.nowLine'),
                                    left: _x(start, now) - 1,
                                    top: 0,
                                    bottom: 0,
                                    width: 2,
                                    child: const IgnorePointer(
                                      child: ColoredBox(
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        return ScrollConfiguration(
          // Let the mouse drag the grid too, not only touch and trackpads.
          behavior: behavior,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Stack(
              children: [
                grid,
                Positioned(
                  left: channelWidth + 0.5 - ResizeHandle.width / 2,
                  top: 0,
                  bottom: 0,
                  width: ResizeHandle.width,
                  child: ResizeHandle(
                    key: const Key('guide.channels.resize'),
                    onStart: () => setState(() => _dragWidth = channelWidth),
                    onUpdate: (dx) => setState(
                      () => _dragWidth = (_dragWidth ?? channelWidth) + dx,
                    ),
                    onEnd: _endDrag,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

typedef _Window = ({DateTime from, DateTime to});

/// Top-left cell: the date at the left edge of the grid and a "now" button.
class _Corner extends StatelessWidget {
  const _Corner({
    required this.controller,
    required this.time,
    required this.start,
    required this.width,
    required this.onNow,
  });

  final ScrollController controller;
  final GuideTime time;
  final DateTime start;
  final double width;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final offset = controller.hasClients
                    ? controller.offset
                    : controller.initialScrollOffset;
                final left = start.add(
                  Duration(
                    seconds: (offset / GuideGrid.pixelsPerMinute * 60).round(),
                  ),
                );
                return Text(
                  formatGuideDate(time, left),
                  key: const Key('guide.date'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                );
              },
            ),
          ),
          TextButton(onPressed: onNow, child: const Text('Now')),
        ],
      ),
    );
  }
}

/// Time labels every half hour, and a marker at the current time.
class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.time,
    required this.start,
    required this.width,
    required this.height,
    required this.window,
    required this.nowX,
  });

  final GuideTime time;
  final DateTime start;
  final double width;
  final double height;
  final _Window window;
  final double nowX;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = <Widget>[];
    // [start] is on a display-zone hour; half-hour steps stay on the
    // half hour across daylight saving changes.
    var tick = start;
    final end = start.add(
      Duration(minutes: (width / GuideGrid.pixelsPerMinute).round()),
    );
    while (tick.isBefore(end)) {
      if (!tick.isBefore(window.from) && tick.isBefore(window.to)) {
        final local = time.local(tick);
        final midnight = local.hour == 0 && local.minute == 0;
        labels.add(
          Positioned(
            left: tick.difference(start).inMinutes * GuideGrid.pixelsPerMinute,
            top: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: theme.dividerColor)),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                midnight
                    ? '${formatGuideDate(time, tick)} ${time.formatLocalHm(tick)}'
                    : time.formatLocalHm(tick),
                style: midnight
                    ? theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      )
                    : theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
              ),
            ),
          ),
        );
      }
      tick = tick.add(const Duration(minutes: 30));
    }
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          ...labels,
          Positioned(
            left: nowX - 1,
            bottom: 0,
            width: 2,
            height: 10,
            child: const ColoredBox(color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _ChannelCell extends ConsumerWidget {
  const _ChannelCell({required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return FocusRing(
      radius: 0,
      inset: true,
      child: InkWell(
        onTap: () => openChannel(context, ref, channel),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (channel.number case final number?)
                  ChannelNumber(number, style: theme.textTheme.bodySmall),
                Expanded(
                  child: TruncatedText(
                    keepLastWordAttached(channel.name),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends ConsumerWidget {
  const _GuideRow({
    required this.channel,
    required this.guide,
    required this.time,
    required this.start,
    required this.window,
    required this.now,
    required this.width,
    required this.scroll,
  });

  final LiveStream channel;
  final EpgGuide guide;
  final GuideTime time;
  final DateTime start;
  final _Window window;
  final DateTime now;
  final double width;

  /// The grid's horizontal scroll, for keeping titles in view.
  final ScrollController scroll;

  double _x(DateTime t) =>
      t.difference(start).inSeconds / 60 * GuideGrid.pixelsPerMinute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final guideNow = time.unadjust(now);
    final programs = guide.between(
      channel,
      time.unadjust(window.from),
      time.unadjust(window.to),
    );
    final cells = <Widget>[];
    for (final p in programs) {
      final left = math.max(0.0, _x(time.adjust(p.start)));
      final right = math.min(width, _x(time.adjust(p.stop)));
      if (right <= left) continue;
      final airing = p.isAiringAt(guideNow);
      cells.add(
        Positioned(
          left: left,
          width: right - left,
          top: 0,
          bottom: 0,
          child: _ProgramCell(
            key: Key(
              'guide.program.${channel.id}.'
              '${p.start.millisecondsSinceEpoch ~/ 1000}',
            ),
            program: p,
            label: time.formatRange(p.start, p.stop),
            airing: airing,
            left: left,
            width: right - left,
            scroll: scroll,
            onTap: airing
                ? () => openChannel(context, ref, channel)
                : () => _showDetails(context, p),
          ),
        ),
      );
    }
    if (cells.isEmpty && guide.programsFor(channel).isEmpty) {
      cells.add(
        Positioned(
          left: math.max(0.0, _x(window.from)) + 8,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No guide information',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Stack(children: cells),
    );
  }

  void _showDetails(BuildContext context, EpgProgram p) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(p.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${channel.name} · ${formatGuideDate(time, time.adjust(p.start))} '
              '${time.formatRange(p.start, p.stop)}',
            ),
            if (p.category case final category?) ...[
              const SizedBox(height: 4),
              Text(category, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (p.description case final description?) ...[
              const SizedBox(height: 12),
              Text(description),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ProgramCell extends StatelessWidget {
  const _ProgramCell({
    super.key,
    required this.program,
    required this.label,
    required this.airing,
    required this.onTap,
    required this.left,
    required this.width,
    required this.scroll,
  });

  final EpgProgram program;
  final String label;
  final bool airing;
  final VoidCallback onTap;

  /// Position and width of the block in the grid.
  final double left;
  final double width;
  final ScrollController scroll;

  /// Text keeps at least this much of the block when pinned.
  static const _minTextWidth = 60.0;

  /// Space around the block, and inside it around the text.
  static const margin = EdgeInsets.all(2);
  static const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 4);

  static const _radius = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: FocusRing(
        radius: _radius,
        inset: true,
        child: Material(
          color: airing ? AppColors.hover : AppColors.card,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Tooltip(
              message: '$label  ${program.title}',
              waitDuration: const Duration(milliseconds: 600),
              child: ListenableBuilder(
                listenable: scroll,
                // A block that starts left of the visible area keeps its text
                // at the visible edge instead of scrolled out of sight.
                builder: (context, child) {
                  final offset = scroll.hasClients
                      ? scroll.offset
                      : scroll.initialScrollOffset;
                  final double inset = (offset - left).clamp(
                    0.0,
                    math.max(0.0, width - _minTextWidth),
                  );
                  return Padding(
                    padding: EdgeInsets.only(left: inset),
                    child: child,
                  );
                },
                child: Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        program.title,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        // textMuted is too faint on hover for small text.
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: airing ? AppColors.textSecondary : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [name] with a trailing mark like `◉` (catch-up) kept on the same line
/// as the word before it, so it never wraps onto a line of its own. A mark
/// is a last word of at most 4 characters without letters or digits.
@visibleForTesting
String keepLastWordAttached(String name) {
  final match = RegExp(r'^(.*\S)\s+(\S{1,4})$').firstMatch(name.trimRight());
  if (match == null || _letterOrDigit.hasMatch(match[2]!)) return name;
  // A no-break space instead of the last space.
  return '${match[1]}\u00A0${match[2]}';
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
