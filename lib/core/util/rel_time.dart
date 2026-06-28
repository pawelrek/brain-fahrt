/// Port of the prototype's `relTime(minsAgo)` to real timestamps.
///
/// Returns "just now" / "Nm ago" / "Nh ago" / "Nd ago" / "Nw ago".
String relativeTime(DateTime then, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final mins = n.difference(then).inSeconds / 60.0;
  if (mins < 1) return 'just now';
  if (mins < 60) return '${mins.round()}m ago';
  final hours = mins / 60;
  if (hours < 24) return '${hours.round()}h ago';
  final days = hours / 24;
  if (days < 7) return '${days.round()}d ago';
  return '${(days / 7).round()}w ago';
}
