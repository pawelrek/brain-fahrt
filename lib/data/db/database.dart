import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/log/app_log.dart';
import '../../core/util/id.dart';
import '../models/enums.dart';

part 'database.g.dart';

/// Buckets — colored lists on the board. `colorKey` indexes the palette (it
/// equals the id for seed buckets; user-created buckets pick a free slot).
class Buckets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shape => textEnum<BucketShape>()();
  TextColumn get colorKey => text()();
  IntColumn get sortOrder => integer()();
  IntColumn get createdAt => integer()(); // epoch millis
  TextColumn get description =>
      text().withDefault(const Constant(''))();
  TextColumn get keywords =>
      text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Corrections — user-supplied labelling corrections for the router.
class Corrections extends Table {
  TextColumn get id => text()();
  TextColumn get note => text()();
  TextColumn get bucketId => text()();
  IntColumn get createdAt => integer()(); // epoch millis

  @override
  Set<Column> get primaryKey => {id};
}

/// Items — captured notes. `bucketId == null` => Unsorted; `type == null` for
/// list-shaped buckets.
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get bucketId => text().nullable()();
  TextColumn get type => textEnum<ItemType>().nullable()();
  TextColumn get summary => text()();
  TextColumn get transcript => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()(); // epoch millis

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Buckets, Items, Corrections])
class AppDatabase extends _$AppDatabase {
  /// Production opens an on-device file via drift_flutter; tests inject an
  /// in-memory executor.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'slop'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(buckets, buckets.description);
            await m.addColumn(buckets, buckets.keywords);
            await m.createTable(corrections);
          }
          if (from < 3) {
            // Backfill routing keywords + descriptions on the seed buckets, ONLY
            // where the user hasn't set their own, so the LLM routes by content
            // (e.g. "pill"≠groceries) instead of guessing by bucket name.
            for (final e in seedBucketMetadata.entries) {
              await customStatement(
                "UPDATE buckets SET description = ?, keywords = ? "
                "WHERE id = ? AND (keywords = '' OR keywords IS NULL)",
                [e.value.$1, e.value.$2, e.key],
              );
            }
          }
        },
      );

  /// Default routing metadata (description, keywords) for the seed buckets,
  /// applied by the v3 migration above and at first-launch seeding.
  static const Map<String, (String, String)> seedBucketMetadata = {
    'shopping': (
      'things to buy',
      'buy, groceries, store, food, milk, bread, supermarket, purchase'
    ),
    'todos': (
      'tasks, chores and reminders',
      'task, todo, do, chore, remind, reminder, call, email, errand, pick up, give'
    ),
    'ideas': (
      'ideas and thoughts',
      'idea, maybe, thought, concept, brainstorm, what if'
    ),
    // Only the four shipped seed buckets get default metadata; user-created
    // project buckets keep whatever the user sets — the v3 migration only
    // ever wrote WHERE the row exists.
    'general': ('general project notes', 'general, misc, note, other'),
  };

  /// Buckets in board order.
  Stream<List<Bucket>> watchBuckets() => (select(buckets)
        ..orderBy([(b) => OrderingTerm(expression: b.sortOrder)]))
      .watch();

  /// All items, oldest first (the UI groups + sorts per card/section).
  Stream<List<Item>> watchItems() => (select(items)
        ..orderBy([
          (i) => OrderingTerm(expression: i.createdAt, mode: OrderingMode.asc)
        ]))
      .watch();

  Future<void> upsertItem(ItemsCompanion item) =>
      into(items).insertOnConflictUpdate(item);

  Future<void> setItemDone(String id, bool done) =>
      (update(items)..where((i) => i.id.equals(id)))
          .write(ItemsCompanion(done: Value(done)));

  Future<void> deleteItem(String id) async {
    await (delete(items)..where((i) => i.id.equals(id))).go();
    AppLog.instance.log('db', 'deleted item $id');
  }

  Future<void> updateItemSummary(String id, String summary) async {
    await (update(items)..where((i) => i.id.equals(id)))
        .write(ItemsCompanion(summary: Value(summary)));
    AppLog.instance.log('db', 'edited item $id');
  }

  /// Apply a background routing patch to a provisionally-filed item.
  /// Guards: the row must still exist, its summary must equal
  /// [expectedSummary] (the user hasn't edited it) AND its bucketId must
  /// equal [expectedBucketId] — the value the controller filed provisionally.
  /// If the user moved the item during the routing window the WHOLE patch is
  /// skipped. bucketId is only written if the row's bucketId is still null
  /// (an explicit "to `<bucket>`" filing is never overridden). Returns true
  /// iff a write happened.
  Future<bool> applyRoutePatch(
    String id, {
    required String expectedSummary,
    required String? expectedBucketId,
    required String summary,
    String? bucketId,
    ItemType? type,
  }) async {
    return transaction(() async {
      final row = await (select(items)..where((i) => i.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        AppLog.instance.log('db', 'route patch skipped(deleted) for $id');
        return false;
      }
      if (row.summary != expectedSummary) {
        AppLog.instance.log('db', 'route patch skipped(user edited) for $id');
        return false;
      }
      if (row.bucketId != expectedBucketId) {
        AppLog.instance.log('db', 'route patch skipped(user moved) for $id');
        return false;
      }
      await (update(items)..where((i) => i.id.equals(id))).write(
        ItemsCompanion(
          summary: Value(summary),
          // type may be null — that's a legitimate "still untyped" outcome.
          // Belt-and-braces: provisional rows are always untyped, so only
          // write when the row's type is still null (implied by the guards
          // above, but never clobber a type that appeared in the window).
          type: row.type == null ? Value(type) : const Value.absent(),
          // Only file into a bucket if the row is still Unsorted.
          bucketId:
              row.bucketId == null ? Value(bucketId) : const Value.absent(),
        ),
      );
      AppLog.instance.log('db', 'route patch applied for $id');
      return true;
    });
  }

  /// Create a new bucket at the end of the board.
  ///
  /// The select + insert share one SQLite transaction to prevent a TOCTOU race
  /// where two concurrent calls read the same maxOrder and produce duplicate
  /// sortOrder values.
  Future<void> insertBucket({
    required String id,
    required String name,
    required BucketShape shape,
    required String colorKey,
    String description = '',
    String keywords = '',
  }) async {
    await transaction(() async {
      final existing = await select(buckets).get();
      final maxOrder =
          existing.fold<int>(-1, (m, b) => b.sortOrder > m ? b.sortOrder : m);
      await into(buckets).insert(BucketsCompanion.insert(
        id: id,
        name: name,
        shape: shape,
        colorKey: colorKey,
        sortOrder: maxOrder + 1,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        description: Value(description),
        keywords: Value(keywords),
      ));
    });
    AppLog.instance.log('db', 'created bucket $name ($id)');
  }

  /// Update optional metadata fields on a bucket (name, description, keywords).
  Future<void> updateBucketMeta(
    String id, {
    String? name,
    String? description,
    String? keywords,
  }) async {
    await (update(buckets)..where((b) => b.id.equals(id))).write(
      BucketsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        description:
            description != null ? Value(description) : const Value.absent(),
        keywords:
            keywords != null ? Value(keywords) : const Value.absent(),
      ),
    );
    AppLog.instance.log('db', 'updated bucket meta $id');
  }

  /// Move an item to a different bucket and optionally set its type.
  Future<void> moveItemToBucket(
    String itemId,
    String? bucketId, {
    ItemType? type,
  }) async {
    await (update(items)..where((i) => i.id.equals(itemId))).write(
      ItemsCompanion(
        bucketId: Value(bucketId),
        // Always WRITE type (null clears it): moving to a list/Unsorted must
        // drop a stale project type, moving to a project sets it.
        type: Value(type),
      ),
    );
    AppLog.instance.log('db', 'moved item $itemId -> bucket $bucketId');
  }

  /// Insert a new correction note linked to a bucket.
  Future<void> insertCorrection(String note, String bucketId) async {
    await into(corrections).insert(CorrectionsCompanion.insert(
      id: newId('c'),
      note: note,
      bucketId: bucketId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    AppLog.instance.log('db', 'inserted correction for bucket $bucketId');
  }

  /// Most-recent [limit] corrections, newest first.
  Future<List<Correction>> recentCorrections(int limit) =>
      (select(corrections)
            ..orderBy([
              (c) =>
                  OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .get();

  /// All corrections as a reactive stream, newest first.
  Stream<List<Correction>> watchCorrections() =>
      (select(corrections)
            ..orderBy([
              (c) =>
                  OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> renameBucket(String id, String name) async {
    await (update(buckets)..where((b) => b.id.equals(id)))
        .write(BucketsCompanion(name: Value(name)));
    AppLog.instance.log('db', 'renamed $id -> $name');
  }

  /// Delete a bucket; its items move to Unsorted (bucketId = null) rather than
  /// being destroyed.
  ///
  /// Corrections referencing this bucket are also deleted: recentCorrections()
  /// applies a limit, so stale corrections for a dead bucket would consume that
  /// budget and degrade router few-shot quality.
  Future<void> deleteBucket(String id) async {
    await transaction(() async {
      await (update(items)..where((i) => i.bucketId.equals(id)))
          .write(const ItemsCompanion(bucketId: Value(null)));
      await (delete(corrections)..where((c) => c.bucketId.equals(id))).go();
      await (delete(buckets)..where((b) => b.id.equals(id))).go();
    });
    AppLog.instance.log('db', 'deleted bucket $id (items -> Unsorted)');
  }

  Future<int> bucketCount() async =>
      (await customSelect('SELECT COUNT(*) AS c FROM buckets').getSingle())
          .read<int>('c');
}
