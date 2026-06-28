import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Severity of a [LogEvent].
enum LogLevel { debug, info, warn, error }

/// A single timestamped log line.
@immutable
class LogEvent {
  const LogEvent(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
}

/// In-app event log: a reactive, bounded ring buffer of recent events so the
/// developer can see what the pipeline is doing (model load times, transcripts,
/// routing decisions, errors, CRUD) without a debugger attached.
///
/// Singleton via [instance]; a [ChangeNotifier] so the Logs screen rebuilds
/// reactively. Append-only via [log]; oldest events are evicted past [_maxEvents].
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const int _maxEvents = 500;
  static const int _maxMessageLen = 8000;

  final ListQueue<LogEvent> _events = ListQueue<LogEvent>();

  /// Immutable snapshot, oldest-first. The Logs screen reverses for display.
  List<LogEvent> get events => List.unmodifiable(_events);

  /// Append an event. Safe to call from anywhere (best-effort — a misbehaving
  /// listener could still throw via notifyListeners).
  void log(String tag, String message, {LogLevel level = LogLevel.info}) {
    final msg = message.length > _maxMessageLen
        ? '${message.substring(0, _maxMessageLen)}…'
        : message;
    _events.addLast(LogEvent(DateTime.now(), level, tag, msg));
    while (_events.length > _maxEvents) {
      _events.removeFirst();
    }
    // Mirror to logcat so on-device logs (especially errors) are greppable via
    // `adb logcat | grep 'BF\['` without opening the in-app Logs screen.
    debugPrint('BF[$tag/${level.name}] $msg');
    notifyListeners();
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }
}
