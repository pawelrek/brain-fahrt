import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:slop/data/db/database.dart';
import 'package:slop/data/models/enums.dart';

import 'helpers.dart';

/// Inserts a provisionally-filed item and returns its row.
Future<Item> _insertItem(
  AppDatabase db, {
  required String id,
  required String summary,
  String? bucketId,
  ItemType? type,
}) async {
  await db.upsertItem(ItemsCompanion.insert(
    id: id,
    summary: summary,
    transcript: 'transcript of $summary',
    createdAt: DateTime.now().millisecondsSinceEpoch,
    bucketId: Value(bucketId),
    type: Value(type),
  ));
  return (await db.watchItems().first).firstWhere((i) => i.id == id);
}

void main() {
  test('applyRoutePatch applies when summary matches', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    await _insertItem(db, id: 'i1', summary: 'provisional title');
    final applied = await db.applyRoutePatch(
      'i1',
      expectedSummary: 'provisional title',
      expectedBucketId: null,
      summary: 'routed title',
      bucketId: 'devhub',
      type: ItemType.improvement,
    );

    expect(applied, isTrue);
    final row = (await db.watchItems().first).firstWhere((i) => i.id == 'i1');
    expect(row.summary, 'routed title');
    expect(row.bucketId, 'devhub');
    expect(row.type, ItemType.improvement);
  });

  test('applyRoutePatch skipped when the user edited the summary first',
      () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    await _insertItem(db, id: 'i2', summary: 'provisional title');
    await db.updateItemSummary('i2', 'my own words');

    final applied = await db.applyRoutePatch(
      'i2',
      expectedSummary: 'provisional title',
      expectedBucketId: null,
      summary: 'routed title',
      bucketId: 'devhub',
      type: ItemType.bug,
    );

    expect(applied, isFalse);
    final row = (await db.watchItems().first).firstWhere((i) => i.id == 'i2');
    expect(row.summary, 'my own words'); // user's edit wins
    expect(row.bucketId, isNull);
    expect(row.type, isNull);
  });

  test('applyRoutePatch skipped when the item was deleted', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    await _insertItem(db, id: 'i3', summary: 'provisional title');
    await db.deleteItem('i3');

    final applied = await db.applyRoutePatch(
      'i3',
      expectedSummary: 'provisional title',
      expectedBucketId: null,
      summary: 'routed title',
      bucketId: 'devhub',
      type: ItemType.bug,
    );

    expect(applied, isFalse);
    expect(
      (await db.watchItems().first).where((i) => i.id == 'i3'),
      isEmpty,
    );
  });

  test('applyRoutePatch skipped ENTIRELY when the user moved the item during '
      'the routing window', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    // Provisionally filed to Unsorted; the user moves it before the patch.
    await _insertItem(db, id: 'i4', summary: 'title a');
    await db.moveItemToBucket('i4', 'webapp');

    final applied = await db.applyRoutePatch(
      'i4',
      expectedSummary: 'title a',
      expectedBucketId: null, // the provisional value at commit time
      summary: 'title a routed',
      bucketId: 'general',
      type: ItemType.issue,
    );

    expect(applied, isFalse);
    final row = (await db.watchItems().first).firstWhere((i) => i.id == 'i4');
    expect(row.bucketId, 'webapp'); // user's move wins
    expect(row.summary, 'title a'); // summary NOT patched either
    expect(row.type, isNull); // type NOT patched either
  });

  test('applyRoutePatch skipped when the user moved the item to Unsorted '
      'during the routing window (not re-filed)', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    // Explicitly filed to webapp at commit; user moves it back to Unsorted.
    await _insertItem(db, id: 'i7', summary: 'title c', bucketId: 'webapp');
    await db.moveItemToBucket('i7', null);

    final applied = await db.applyRoutePatch(
      'i7',
      expectedSummary: 'title c',
      expectedBucketId: 'webapp', // the provisional value at commit time
      summary: 'title c routed',
      bucketId: 'general',
      type: ItemType.bug,
    );

    expect(applied, isFalse);
    final row = (await db.watchItems().first).firstWhere((i) => i.id == 'i7');
    expect(row.bucketId, isNull); // stays in Unsorted — never re-filed
    expect(row.summary, 'title c');
    expect(row.type, isNull);
  });

  test('applyRoutePatch applies on a same-state row: explicit filing keeps '
      'its bucket, summary/type written; a still-null bucket is written',
      () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    // Same-state explicit filing: bucket preserved, summary/type written.
    await _insertItem(db, id: 'i8', summary: 'title d', bucketId: 'webapp');
    final appliedA = await db.applyRoutePatch(
      'i8',
      expectedSummary: 'title d',
      expectedBucketId: 'webapp',
      summary: 'title d routed',
      bucketId: 'general', // LLM disagrees — must not move the item
      type: ItemType.issue,
    );
    expect(appliedA, isTrue);
    var row = (await db.watchItems().first).firstWhere((i) => i.id == 'i8');
    expect(row.bucketId, 'webapp'); // bucket preserved
    expect(row.summary, 'title d routed');
    expect(row.type, ItemType.issue);

    // Same-state Unsorted: a still-null bucket is written.
    await _insertItem(db, id: 'i5', summary: 'title b');
    final appliedB = await db.applyRoutePatch(
      'i5',
      expectedSummary: 'title b',
      expectedBucketId: null,
      summary: 'title b routed',
      bucketId: 'general',
      type: null,
    );
    expect(appliedB, isTrue);
    row = (await db.watchItems().first).firstWhere((i) => i.id == 'i5');
    expect(row.bucketId, 'general');
  });

  test('applyRoutePatch with null type keeps the row untyped', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    // Provisional rows are always untyped at insert.
    await _insertItem(db, id: 'i6', summary: 'typed title', bucketId: 'devhub');
    final applied = await db.applyRoutePatch(
      'i6',
      expectedSummary: 'typed title',
      expectedBucketId: 'devhub',
      summary: 'typed title routed',
      bucketId: 'devhub',
      type: null,
    );

    expect(applied, isTrue);
    final row = (await db.watchItems().first).firstWhere((i) => i.id == 'i6');
    expect(row.type, isNull); // legitimate "still untyped" outcome
    expect(row.summary, 'typed title routed');
  });
}
