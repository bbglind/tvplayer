import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Result of [showTimeZonePicker]: [zone] null means the device's zone.
typedef TimeZoneChoice = ({String? zone});

/// Lets the user pick an IANA time zone, or the device's zone. Returns null
/// when cancelled.
Future<TimeZoneChoice?> showTimeZonePicker(
  BuildContext context, {
  required String? current,
  required String deviceZone,
}) => showDialog<TimeZoneChoice>(
  context: context,
  builder: (context) =>
      _TimeZoneDialog(current: current, deviceZone: deviceZone),
);

class _TimeZoneDialog extends StatefulWidget {
  const _TimeZoneDialog({required this.current, required this.deviceZone});

  final String? current;
  final String deviceZone;

  @override
  State<_TimeZoneDialog> createState() => _TimeZoneDialogState();
}

class _TimeZoneDialogState extends State<_TimeZoneDialog> {
  final _zones = GuideTime.zoneNames();
  String _query = '';

  static Widget _ringed(Widget tile) =>
      FocusRing(radius: AppRadius.small, inset: true, child: tile);

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase().replaceAll(' ', '_');
    final matches = [
      for (final z in _zones)
        if (q.isEmpty || z.toLowerCase().contains(q)) z,
    ];
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Guide time zone'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              key: const Key('timeZone.search'),
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search, e.g. Stockholm',
                isDense: true,
                // The dialog itself is `surface`.
                fillColor: AppColors.card,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _ringed(
                      ListTile(
                        dense: true,
                        selected: widget.current == null,
                        title: const Text('Device time zone'),
                        subtitle: Text(widget.deviceZone),
                        onTap: () => Navigator.pop(context, (zone: null)),
                      ),
                    );
                  }
                  final zone = matches[i - 1];
                  return _ringed(
                    ListTile(
                      dense: true,
                      selected: zone == widget.current,
                      title: Text(zone.replaceAll('_', ' ')),
                      trailing: Text(GuideTime.named(zone).offsetAt(now)),
                      onTap: () => Navigator.pop(context, (zone: zone)),
                    ),
                  );
                },
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
      ],
    );
  }
}
