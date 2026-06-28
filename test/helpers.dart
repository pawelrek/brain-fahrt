import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:slop/data/db/database.dart';
import 'package:slop/data/providers.dart';
import 'package:slop/data/seed.dart';

/// A fresh in-memory database, seeded with the default buckets + demo items.
Future<AppDatabase> seededMemoryDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedDatabaseIfEmpty(db, withDemoItems: true);
  return db;
}

/// Wraps [child] in a ProviderScope bound to [db] + a MaterialApp, with
/// animations disabled so infinite-repeat painters (waveform/pulse/spinner)
/// render their static end-state and `pumpAndSettle` terminates.
Widget testHarness({
  required Widget child,
  required AppDatabase db,
  List<Override> extraOverrides = const [],
}) {
  final screen = child;
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      ...extraOverrides,
    ],
    // Inject disableAnimations BELOW MaterialApp's own MediaQuery (via builder),
    // so every route — including pushed overlays — renders infinite-repeat
    // painters (waveform/pulse/spinner) as static end-states and pumpAndSettle
    // terminates. A MediaQuery above MaterialApp would be overridden by the
    // app's view-derived MediaQuery and have no effect.
    child: MaterialApp(
      builder: (context, navChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: navChild!,
      ),
      home: screen,
    ),
  );
}
