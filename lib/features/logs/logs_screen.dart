import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';

/// Developer log screen — shows AppLog events newest-first, with
/// reactive rebuild via AnimatedBuilder on AppLog.instance.
class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DotColors.canvas,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: AppLog.instance,
          builder: (context, _) {
            final events = AppLog.instance.events.reversed.toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LogsHeader(events: events),
                Expanded(
                  child: events.isEmpty
                      ? Center(
                          child: Text(
                            'No events yet',
                            style: DotText.font(
                              size: 15,
                              weight: FontWeight.w500,
                              color: DotColors.faint2,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: events.length,
                          itemBuilder: (_, i) => _LogRow(event: events[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _LogsHeader extends StatelessWidget {
  const _LogsHeader({required this.events});

  final List<LogEvent> events;

  String _buildDump() {
    // events here are newest-first; dump in that order
    final buf = StringBuffer();
    for (final e in events) {
      final ts = _formatTime(e.time);
      final lvl = e.level.name.toUpperCase().padRight(5);
      buf.writeln('$ts [$lvl] ${e.tag}: ${e.message}');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: DotPad.header,
      child: Row(
        children: [
          // Back chevron
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  Icons.chevron_left,
                  size: 26,
                  color: DotColors.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text('Logs', style: DotText.wordmark),
          ),
          // Clear button
          GestureDetector(
            onTap: () {
              AppLog.instance.log('ui', 'logs cleared');
              AppLog.instance.clear();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                'Clear',
                style: DotText.font(
                  size: 14,
                  weight: FontWeight.w600,
                  color: DotColors.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Copy all button
          GestureDetector(
            onTap: () {
              AppLog.instance.log('ui', 'logs copied');
              Clipboard.setData(ClipboardData(text: _buildDump()));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                'Copy all',
                style: DotText.font(
                  size: 14,
                  weight: FontWeight.w600,
                  color: DotColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _LogRow extends StatelessWidget {
  const _LogRow({required this.event});

  final LogEvent event;

  Color _textColor() {
    switch (event.level) {
      case LogLevel.error:
        // Coral reads better than classic red on the dark canvas.
        return DotReds.coral;
      case LogLevel.warn:
        // Amber-ish accent (shopping/ocher) — webapp is dusty rose now.
        return bucketColorsFor('shopping').accent;
      case LogLevel.info:
        return DotColors.ink;
      case LogLevel.debug:
        return DotColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _textColor();
    final ts = _formatTime(event.time);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp — monospace-ish via tabular figures
          Text(
            ts,
            style: DotText.timer.copyWith(
              fontSize: 11,
              color: DotColors.faint2,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 8),
          // Tag
          Text(
            event.tag,
            style: DotText.font(
              size: 12,
              weight: FontWeight.w700,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 6),
          // Message
          Expanded(
            child: Text(
              event.message,
              style: DotText.font(
                size: 12,
                weight: FontWeight.w500,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format a [DateTime] as HH:mm:ss.SSS without the intl package.
String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  final ms = t.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}
