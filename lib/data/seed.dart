import 'package:drift/drift.dart';

import 'db/database.dart';
import 'models/enums.dart';

/// Default board — four seed buckets (General = project; Shopping, To-dos,
/// Ideas = list). `colorKey == id`. Only General is a seeded project bucket;
/// users create their own project buckets.
const List<({String id, String name, BucketShape shape})> _seedBuckets = [
  (id: 'general', name: 'General', shape: BucketShape.project),
  (id: 'shopping', name: 'Shopping', shape: BucketShape.list),
  (id: 'todos', name: 'To-dos', shape: BucketShape.list),
  (id: 'ideas', name: 'Ideas', shape: BucketShape.list),
];

/// Seed items — the prototype's `SEED_ITEMS`, so the board feels alive.
/// `minsAgo` is converted to a real `createdAt` at seed time.
const List<
    ({
      String id,
      String bucket,
      ItemType? type,
      String summary,
      String transcript,
      int minsAgo,
      bool done,
    })> _seedItems = [
  // general (project)
  (
    id: 's2',
    bucket: 'general',
    type: ItemType.bug,
    summary: 'Run timer keeps counting after a job is killed',
    transcript:
        'noticed the run timer keeps ticking even after I kill the job, the elapsed number is wrong',
    minsAgo: 180,
    done: false,
  ),
  (
    id: 's3',
    bucket: 'general',
    type: ItemType.issue,
    summary: 'GPU memory spikes on the eval split',
    transcript:
        'memory spikes hard whenever it hits the eval split, almost OOMs on the big runs',
    minsAgo: 1500,
    done: false,
  ),
  (
    id: 's6',
    bucket: 'general',
    type: ItemType.improvement,
    summary: 'Draft a one-pager on the offline-first pitch',
    transcript:
        'I should write a quick one pager on the whole offline first pitch for the team',
    minsAgo: 320,
    done: false,
  ),
  // shopping (list)
  (
    id: 's7',
    bucket: 'shopping',
    type: null,
    summary: 'Olive oil and sea salt',
    transcript: 'grab olive oil and some flaky sea salt',
    minsAgo: 30,
    done: false,
  ),
  (
    id: 's8',
    bucket: 'shopping',
    type: null,
    summary: 'Dish soap',
    transcript: 'we are out of dish soap',
    minsAgo: 70,
    done: true,
  ),
  (
    id: 's9',
    bucket: 'shopping',
    type: null,
    summary: 'Lightbulbs for the hallway',
    transcript: 'need lightbulbs for the hallway, the warm ones',
    minsAgo: 240,
    done: false,
  ),
  // todos (list)
  (
    id: 's10',
    bucket: 'todos',
    type: null,
    summary: 'Reply to the landlord about the lease',
    transcript: 'reply to the landlord about renewing the lease',
    minsAgo: 55,
    done: false,
  ),
  (
    id: 's11',
    bucket: 'todos',
    type: null,
    summary: 'Move the car before street cleaning',
    transcript: 'move the car before street cleaning on thursday',
    minsAgo: 200,
    done: false,
  ),
  // ideas (list)
  (
    id: 's12',
    bucket: 'ideas',
    type: null,
    summary: 'A capture that auto-tags people it hears named',
    transcript:
        'what if a capture could auto tag people whenever it hears their name mentioned',
    minsAgo: 130,
    done: false,
  ),
  (
    id: 's13',
    bucket: 'ideas',
    type: null,
    summary: 'Daily "what did I capture" recap on the lock screen',
    transcript:
        'a little daily recap of what I captured, right on the lock screen',
    minsAgo: 880,
    done: false,
  ),
];

/// Seed the default buckets the first time the app runs (no-op if buckets
/// already exist). The shipped app starts with a CLEAN board (no demo notes);
/// pass [withDemoItems] true only for tests/screenshots.
Future<void> seedDatabaseIfEmpty(AppDatabase db, {bool withDemoItems = false}) async {
  if (await db.bucketCount() > 0) return;

  final now = DateTime.now();
  int at(int minsAgo) =>
      now.subtract(Duration(minutes: minsAgo)).millisecondsSinceEpoch;

  await db.batch((b) {
    var order = 0;
    b.insertAll(db.buckets, [
      for (final s in _seedBuckets)
        BucketsCompanion.insert(
          id: s.id,
          name: s.name,
          shape: s.shape,
          colorKey: s.id,
          sortOrder: order++,
          createdAt: now.millisecondsSinceEpoch,
          // Routing metadata so fresh installs route by content, not just name.
          description: Value(AppDatabase.seedBucketMetadata[s.id]?.$1 ?? ''),
          keywords: Value(AppDatabase.seedBucketMetadata[s.id]?.$2 ?? ''),
        ),
    ]);
    if (withDemoItems) {
      b.insertAll(db.items, [
        for (final s in _seedItems)
          ItemsCompanion.insert(
            id: s.id,
            bucketId: Value(s.bucket),
            type: Value(s.type),
            summary: s.summary,
            transcript: s.transcript,
            done: Value(s.done),
            createdAt: at(s.minsAgo),
          ),
      ]);
    }
  });
}
