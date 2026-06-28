/// Collision-safe id for locally-created items.
///
/// Microsecond timestamp + a process-monotonic counter, so rapid inserts (and
/// fast widget/integration tests that commit several captures in the same
/// millisecond) never collide.
int _counter = 0;

String newId([String prefix = 'n']) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
