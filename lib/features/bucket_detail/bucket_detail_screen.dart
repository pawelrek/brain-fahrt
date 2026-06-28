import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../core/util/id.dart';
import '../../core/util/rel_time.dart';
import '../../core/widgets/dot_icon.dart';
import '../../core/widgets/type_glyph.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import 'item_actions.dart';

// Palette keys available when creating a new list inline.
const List<String> _colorKeys = [
  'devhub',
  'webapp',
  'general',
  'shopping',
  'todos',
  'ideas',
];

/// Drill-in view for a single bucket — project (sectioned), list (flat
/// checkable), or the synthetic "unsorted" inbox.
class BucketDetailScreen extends ConsumerStatefulWidget {
  const BucketDetailScreen({
    super.key,
    required this.bucketId,
    required this.onBack,
  });

  final String bucketId;
  final VoidCallback onBack;

  @override
  ConsumerState<BucketDetailScreen> createState() =>
      _BucketDetailScreenState();
}

class _BucketDetailScreenState extends ConsumerState<BucketDetailScreen> {
  final Set<String> _selectedIds = {};
  bool _selectionActive = false;

  // Selection mode is a deliberate mode (entered via the header Select button),
  // NOT merely "something is selected" — so checkboxes can appear before the
  // first item is picked.
  bool get _selectionMode => _selectionActive;

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelection() {
    if (!mounted) return;
    setState(() {
      _selectionActive = false;
      _selectedIds.clear();
    });
  }

  void _toggleAll(List<Item> mine) {
    setState(() {
      if (_selectedIds.length == mine.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(mine.map((i) => i.id));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    AppLog.instance.log('ui', 'bucket detail opened ${widget.bucketId}');
  }

  // ---------------------------------------------------------------------------
  // Bulk move
  // ---------------------------------------------------------------------------

  Future<void> _bulkMove(
    BuildContext ctx,
    List<Item> mine,
    Bucket? destination,
  ) async {
    final db = ref.read(databaseProvider);
    final selected = mine.where((i) => _selectedIds.contains(i.id)).toList();
    try {
      for (final item in selected) {
        if (destination == null) {
          // Move to Unsorted
          await db.moveItemToBucket(item.id, null, type: null);
          if (item.bucketId != null) {
            await db.insertCorrection(item.summary, 'unsorted');
          }
        } else if (destination.shape == BucketShape.list) {
          await db.moveItemToBucket(item.id, destination.id, type: null);
          if (item.bucketId != destination.id) {
            await db.insertCorrection(item.summary, destination.id);
          }
        } else {
          // project bucket
          final t = item.type ?? ItemType.improvement;
          await db.moveItemToBucket(item.id, destination.id, type: t);
          if (item.bucketId != destination.id) {
            await db.insertCorrection(item.summary, destination.id);
          }
        }
      }
    } catch (e, st) {
      AppLog.instance.log('error', 'bulkMove failed: $e\n$st');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Could not move items.')),
        );
      }
      return;
    }
    _exitSelection();
  }

  // ---------------------------------------------------------------------------
  // Bulk delete
  // ---------------------------------------------------------------------------

  Future<void> _bulkDelete(BuildContext ctx, List<Item> mine) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: DotColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete $count item${count == 1 ? '' : 's'}?',
          style: DotText.font(size: 16.5, weight: FontWeight.w700),
        ),
        content: Text(
          'This cannot be undone.',
          style:
              DotText.font(size: 14, weight: FontWeight.w500, color: DotColors.muted),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'Cancel',
              style: DotText.font(
                  size: 14, weight: FontWeight.w600, color: DotColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'Delete',
              style: DotText.font(
                  size: 14, weight: FontWeight.w700, color: DotReds.classic),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final db = ref.read(databaseProvider);
    final ids = List<String>.from(_selectedIds);
    try {
      for (final id in ids) {
        await db.deleteItem(id);
      }
    } catch (e, st) {
      AppLog.instance.log('error', 'bulkDelete failed: $e\n$st');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Could not delete items.')),
        );
      }
      return;
    }
    _exitSelection();
  }

  // ---------------------------------------------------------------------------
  // Bulk move picker — bottom sheet
  // ---------------------------------------------------------------------------

  void _showBulkMovePicker(BuildContext ctx, List<Item> mine) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BulkMoveSheet(
        selectedIds: Set.from(_selectedIds),
        mine: mine,
        onPick: (destination) async {
          if (ctx.mounted) Navigator.of(ctx).pop();
          await _bulkMove(ctx, mine, destination);
        },
        onCreateNew: (name, allBuckets) async {
          if (ctx.mounted) Navigator.of(ctx).pop();
          await _createAndMove(ctx, name, mine, allBuckets);
        },
      ),
    );
  }

  Future<void> _createAndMove(
    BuildContext ctx,
    String name,
    List<Item> mine,
    List<Bucket> existingBuckets,
  ) async {
    // Pick a colorKey not already used by existing buckets.
    final usedKeys = existingBuckets.map((b) => b.colorKey).toSet();
    final colorKey = _colorKeys.firstWhere(
      (k) => !usedKeys.contains(k),
      orElse: () => _colorKeys[existingBuckets.length % _colorKeys.length],
    );
    final newBucketId = newId('b');
    final db = ref.read(databaseProvider);
    try {
      await db.insertBucket(
        id: newBucketId,
        name: name,
        shape: BucketShape.list,
        colorKey: colorKey,
      );
      // Build a synthetic destination to avoid re-querying.
      final selected = mine.where((i) => _selectedIds.contains(i.id)).toList();
      for (final item in selected) {
        await db.moveItemToBucket(item.id, newBucketId, type: null);
        if (item.bucketId != newBucketId) {
          await db.insertCorrection(item.summary, newBucketId);
        }
      }
    } catch (e, st) {
      AppLog.instance.log('error', 'createAndMove failed: $e\n$st');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Could not create list and move items.')),
        );
      }
      return;
    }
    _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final bucketId = widget.bucketId;
    final bucketsAsync = ref.watch(bucketsProvider);
    final itemsAsync = ref.watch(itemsProvider);

    final buckets = bucketsAsync.asData?.value ?? const [];
    final allItems = itemsAsync.asData?.value ?? const [];

    final isUnsorted = bucketId == 'unsorted';
    final bucket = isUnsorted
        ? null
        : buckets.cast<Bucket?>().firstWhere(
              (b) => b!.id == bucketId,
              orElse: () => null,
            );

    // [32] If the bucket was deleted while this screen is open, auto-navigate
    // back rather than silently rendering an empty detail view.
    if (!isUnsorted && bucket == null && bucketsAsync.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppLog.instance.log('ui', 'bucket $bucketId deleted — auto-back');
          widget.onBack();
        }
      });
      return const Scaffold(backgroundColor: DotColors.canvas);
    }

    final colors =
        bucketColorsFor(isUnsorted ? 'unsorted' : (bucket?.colorKey ?? 'unsorted'));

    final mine = allItems
        .where((i) => isUnsorted ? i.bucketId == null : i.bucketId == bucketId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final name = isUnsorted ? 'Unsorted' : (bucket?.name ?? '');
    final shape = isUnsorted ? null : bucket?.shape;

    // Remove stale selections (items may have been moved/deleted).
    final mineIds = mine.map((i) => i.id).toSet();
    final stale = _selectedIds.difference(mineIds);
    if (stale.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedIds.removeAll(stale);
            // If external moves/deletes emptied the selection, leave the mode.
            if (_selectedIds.isEmpty) _selectionActive = false;
          });
        }
      });
    }

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: DotColors.canvas,
        bottomNavigationBar: _selectionMode && _selectedIds.isNotEmpty
            ? _BulkActionBar(
                count: _selectedIds.length,
                onMoveTo: () => _showBulkMovePicker(context, mine),
                onDelete: () => _bulkDelete(context, mine),
              )
            : null,
        body: Column(
          children: [
            _Header(
              name: name,
              shape: shape,
              isUnsorted: isUnsorted,
              mine: mine,
              colors: colors,
              selectionMode: _selectionMode,
              selectedCount: _selectedIds.length,
              onBack: () {
                if (_selectionMode) {
                  _exitSelection();
                } else {
                  AppLog.instance.log('ui', 'bucket detail back');
                  widget.onBack();
                }
              },
              onEnterSelection: () => setState(() => _selectionActive = true),
              onToggleAll: () => _toggleAll(mine),
            ),
            Expanded(
              child: _Body(
                isUnsorted: isUnsorted,
                shape: shape,
                mine: mine,
                colors: colors,
                selectionMode: _selectionMode,
                selectedIds: _selectedIds,
                onToggleDone: (item) {
                  AppLog.instance
                      .log('ui', 'toggled item ${item.id} done=${!item.done}');
                  ref.read(databaseProvider).setItemDone(item.id, !item.done);
                },
                onToggleSelect: (item) => _toggleItem(item.id),
                onLongPress: (item) {
                  if (_selectionMode) return; // ignore long-press in selection mode
                  AppLog.instance.log('ui', 'long-press enter selection ${item.id}');
                  setState(() {
                    _selectionActive = true;
                    _selectedIds.add(item.id);
                  });
                },
                onEdit: (item) => showEditItemDialog(context, ref, item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — flat on canvas (Keep open-note), muted icons, accent dot + name
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.shape,
    required this.isUnsorted,
    required this.mine,
    required this.colors,
    required this.selectionMode,
    required this.selectedCount,
    required this.onBack,
    required this.onEnterSelection,
    required this.onToggleAll,
  });

  final String name;
  final BucketShape? shape;
  final bool isUnsorted;
  final List<Item> mine;
  final BucketColors colors;
  final bool selectionMode;
  final int selectedCount;
  final VoidCallback onBack;
  final VoidCallback onEnterSelection;
  final VoidCallback onToggleAll;

  String get _subtitle {
    if (selectionMode) return '$selectedCount selected';
    if (shape == BucketShape.project) {
      return '${mine.length} notes · Improvement · Bug · Issue';
    }
    if (isUnsorted) {
      return '${mine.length} waiting to be filed';
    }
    // list shape
    final remaining = mine.where((i) => !i.done).length;
    return '$remaining of ${mine.length} left';
  }

  String get _displayName {
    if (selectionMode) return '$selectedCount selected';
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final allSelected = mine.isNotEmpty && selectedCount == mine.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8 + topPadding, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nav row — muted icons on canvas, same idiom as the board header.
          Row(
            children: [
              _CircleButton(
                onTap: onBack,
                background: Colors.transparent,
                child: selectionMode
                    ? const Icon(Icons.close_rounded,
                        size: 20, color: DotColors.muted)
                    : const _ChevronLeft(color: DotColors.muted),
              ),
              const Spacer(),
              if (selectionMode)
                // Select all / deselect all
                _CircleButton(
                  onTap: onToggleAll,
                  background: Colors.transparent,
                  child: Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    size: 20,
                    color: DotColors.muted,
                  ),
                )
              else
                // Enter selection mode
                _CircleButton(
                  onTap: onEnterSelection,
                  background: Colors.transparent,
                  child: const Icon(
                    Icons.checklist_rounded,
                    size: 20,
                    color: DotColors.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Title row — 10px accent dot before the name (board-card idiom).
          Row(
            children: [
              if (!selectionMode) ...[
                if (isUnsorted)
                  DotIcon(DotIconName.inbox, size: 22, color: colors.accent)
                else
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
              ],
              Text(
                _displayName,
                style: DotText.screenTitle,
              ),
            ],
          ),
          // Subtitle
          if (!selectionMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _subtitle,
                style: DotText.font(
                  size: 13,
                  weight: FontWeight.w600,
                  color: DotColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _Body extends ConsumerWidget {
  const _Body({
    required this.isUnsorted,
    required this.shape,
    required this.mine,
    required this.colors,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleDone,
    required this.onToggleSelect,
    required this.onLongPress,
    required this.onEdit,
  });

  final bool isUnsorted;
  final BucketShape? shape;
  final List<Item> mine;
  final BucketColors colors;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Item) onToggleDone;
  final void Function(Item) onToggleSelect;
  final void Function(Item) onLongPress;
  final void Function(Item) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
      children: [
        if (isUnsorted) ...[
          _UnsortedHint(),
          ...mine.map((it) => _ItemRow(
                item: it,
                colors: colors,
                isUnsorted: true,
                selectionMode: selectionMode,
                isSelected: selectedIds.contains(it.id),
                onToggleDone: onToggleDone,
                onLongPress: () => onLongPress(it),
                onToggleSelect: () => onToggleSelect(it),
                onEdit: () => onEdit(it),
              )),
        ] else if (shape == BucketShape.project) ...[
          ...ItemType.values.map((t) => _ProjectSection(
                type: t,
                rows: mine.where((i) => i.type == t).toList(),
                colors: colors,
                selectionMode: selectionMode,
                selectedIds: selectedIds,
                onLongPress: (item) => onLongPress(item),
                onToggleSelect: onToggleSelect,
                onEdit: onEdit,
              )),
          // UNTYPED section — items with type == null (router no longer
          // force-defaults; they would otherwise be silently invisible).
          _UntypedSection(
            rows: mine.where((i) => i.type == null).toList(),
            colors: colors,
            selectionMode: selectionMode,
            selectedIds: selectedIds,
            onLongPress: (item) => onLongPress(item),
            onToggleSelect: onToggleSelect,
            onEdit: onEdit,
          ),
        ]
        else ...[
          // list shape — flat checkable rows
          const SizedBox(height: 8),
          ...mine.map((it) => _ItemRow(
                item: it,
                colors: colors,
                isUnsorted: false,
                isList: true,
                selectionMode: selectionMode,
                isSelected: selectedIds.contains(it.id),
                onToggleDone: onToggleDone,
                onLongPress: () => onLongPress(it),
                onToggleSelect: () => onToggleSelect(it),
                onEdit: () => onEdit(it),
              )),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Unsorted hint card
// ---------------------------------------------------------------------------

class _UnsortedHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DotColors.outline, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: brandRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Low-confidence captures land here. Assign one tap.',
              style: DotText.font(
                size: 12.5,
                weight: FontWeight.w500,
                color: DotColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Project section (Improvements / Bugs / Issues)
// ---------------------------------------------------------------------------

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.type,
    required this.rows,
    required this.colors,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onEdit,
  });

  final ItemType type;
  final List<Item> rows;
  final BucketColors colors;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Item) onLongPress;
  final void Function(Item) onToggleSelect;
  final void Function(Item) onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header — accent-tinted glyph + muted small-caps label.
          Row(
            children: [
              TypeGlyph(
                type: type,
                size: 15,
                color: colors.accent.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                type.sectionLabel,
                style: DotText.sectionLabel.copyWith(color: DotColors.muted),
              ),
              const SizedBox(width: 8),
              Text(
                '${rows.length}',
                style: DotText.font(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: DotColors.faint3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                'Nothing here yet',
                style: DotText.font(
                  size: 13.5,
                  weight: FontWeight.w500,
                  color: DotColors.faint3,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            )
          else
            ...rows.map((it) => _ItemRow(
                  item: it,
                  colors: colors,
                  isUnsorted: false,
                  selectionMode: selectionMode,
                  isSelected: selectedIds.contains(it.id),
                  onToggleDone: (_) {},
                  onLongPress: () => onLongPress(it),
                  onToggleSelect: () => onToggleSelect(it),
                  onEdit: () => onEdit(it),
                )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Untyped project section (type == null items)
// ---------------------------------------------------------------------------

class _UntypedSection extends StatelessWidget {
  const _UntypedSection({
    required this.rows,
    required this.colors,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onEdit,
  });

  final List<Item> rows;
  final BucketColors colors;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Item) onLongPress;
  final void Function(Item) onToggleSelect;
  final void Function(Item) onEdit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header — matches _ProjectSection style (no glyph for untyped)
          Row(
            children: [
              Text(
                'UNTYPED',
                style: DotText.sectionLabel.copyWith(color: DotColors.muted),
              ),
              const SizedBox(width: 8),
              Text(
                '${rows.length}',
                style: DotText.font(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: DotColors.faint3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ...rows.map((it) => _ItemRow(
                item: it,
                colors: colors,
                isUnsorted: false,
                selectionMode: selectionMode,
                isSelected: selectedIds.contains(it.id),
                onToggleDone: (_) {},
                onLongPress: () => onLongPress(it),
                onToggleSelect: () => onToggleSelect(it),
                onEdit: () => onEdit(it),
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared item row
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.colors,
    required this.isUnsorted,
    this.isList = false,
    required this.selectionMode,
    required this.isSelected,
    required this.onToggleDone,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onEdit,
  });

  final Item item;
  final BucketColors colors;
  final bool isUnsorted;
  final bool isList;
  final bool selectionMode;
  final bool isSelected;
  final void Function(Item) onToggleDone;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isDone = item.done;
    final timestamp = relativeTime(
      DateTime.fromMillisecondsSinceEpoch(item.createdAt),
    );

    // Show transcript if non-empty and differs from summary (case-insensitive).
    final transcript = item.transcript;
    final showTranscript = transcript.trim().isNotEmpty &&
        transcript.trim().toLowerCase() != item.summary.trim().toLowerCase();

    return GestureDetector(
      onTap: selectionMode ? onToggleSelect : onEdit,
      onLongPress: selectionMode ? null : onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          border: isSelected
              ? Border.all(color: colors.accent, width: 1)
              : const Border(
                  bottom: BorderSide(color: DotColors.hairline, width: 1),
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading: selection checkbox (selection mode) or normal leading
              if (selectionMode)
                _SelectionCheckbox(isSelected: isSelected, accent: colors.accent)
              else if (isList)
                GestureDetector(
                  onTap: () => onToggleDone(item),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    // Pads the tap target around the 13px box.
                    padding: const EdgeInsets.fromLTRB(0, 3, 0, 12),
                    child: _Checkbox(isDone: isDone, accent: colors.accent),
                  ),
                )
              else if (item.type != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: TypeGlyph(
                    type: item.type!,
                    size: 13,
                    color: colors.accent.withValues(alpha: 0.7),
                  ),
                )
              else
                // Null-type items: neutral dot in a 13px slot (board idiom).
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: Center(
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              // Summary + optional transcript + timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.summary,
                      style: DotText.detailSummary.copyWith(
                        // Done list items: muted strikethrough (board idiom).
                        color: isList && isDone && !selectionMode
                            ? DotColors.muted
                            : DotColors.inkBody,
                        decoration: isList && isDone && !selectionMode
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: DotColors.muted,
                      ),
                    ),
                    if (showTranscript) ...[
                      const SizedBox(height: 2),
                      Text(
                        transcript,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DotText.font(
                          size: 11.5,
                          weight: FontWeight.w400,
                          color: DotColors.faint2,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(timestamp, style: DotText.timestamp),
                  ],
                ),
              ),
              // File pill for unsorted items (hide in selection mode to reduce clutter)
              if (isUnsorted && !selectionMode) ...[
                const SizedBox(width: 8),
                _FilePill(colors: colors),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selection checkbox (used in selection mode)
// ---------------------------------------------------------------------------

class _SelectionCheckbox extends StatelessWidget {
  const _SelectionCheckbox({required this.isSelected, required this.accent});

  final bool isSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: isSelected ? accent : Colors.transparent,
        shape: BoxShape.circle,
        border: isSelected
            ? null
            : Border.all(
                color: accent.withValues(alpha: 0.47),
                width: 2,
              ),
      ),
      child: isSelected
          ? Center(
              child: DotIcon(
                DotIconName.check,
                size: 14,
                color: DotColors.canvas,
                weight: 2.8,
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Checkbox (list shape) — Keep-style square outline, same idiom as the board
// cards (13px, r3, accent@55% outline; done = accent fill + canvas check).
// ---------------------------------------------------------------------------

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.isDone, required this.accent});

  final bool isDone;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: isDone
            ? null
            : Border.all(
                color: accent.withValues(alpha: 0.55),
                width: 1.5,
              ),
        color: isDone ? accent : null,
      ),
      child: isDone
          ? Center(
              child: DotIcon(
                DotIconName.check,
                size: 10,
                color: DotColors.canvas,
                weight: 2.6,
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// "File" pill (unsorted rows)
// ---------------------------------------------------------------------------

class _FilePill extends StatelessWidget {
  const _FilePill({required this.colors});

  final BucketColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'File',
        style: DotText.font(
          size: 12.5,
          weight: FontWeight.w700,
          color: colors.ink,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable 40-dp circle button
// ---------------------------------------------------------------------------

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.onTap,
    required this.background,
    required this.child,
  });

  final VoidCallback? onTap;
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chevron left (back icon — not in DotIconName so drawn inline)
// ---------------------------------------------------------------------------

class _ChevronLeft extends StatelessWidget {
  const _ChevronLeft({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _ChevronPainter(color: color),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale 24×24 viewBox to actual size
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // M15 5 l-7 7 7 7
    final path = Path()
      ..moveTo(15, 5)
      ..relativeLineTo(-7, 7)
      ..relativeLineTo(7, 7);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Bulk action bar (bottom of screen when items are selected)
// ---------------------------------------------------------------------------

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.count,
    required this.onMoveTo,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onMoveTo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: DotColors.surface,
          border: Border(top: BorderSide(color: DotColors.hairline, width: 1)),
          boxShadow: DotShadow.sheet,
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
        child: Row(
          children: [
            // Move to…
            Expanded(
              child: GestureDetector(
                onTap: onMoveTo,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DotColors.ink,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dark marks on the light (ink-filled) pill.
                      Icon(Icons.drive_file_move_outline,
                          size: 18, color: DotColors.canvas),
                      const SizedBox(width: 8),
                      Text(
                        'Move to…',
                        style: DotText.font(
                            size: 14.5,
                            weight: FontWeight.w600,
                            color: DotColors.canvas),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Delete
            GestureDetector(
              onTap: onDelete,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: DotReds.classic.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: DotReds.classic),
                    const SizedBox(width: 6),
                    Text(
                      'Delete',
                      style: DotText.font(
                          size: 14.5,
                          weight: FontWeight.w600,
                          color: DotReds.classic),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bulk move picker sheet (local to this file — mirrors _BucketPickerSheet style)
// ---------------------------------------------------------------------------

class _BulkMoveSheet extends ConsumerWidget {
  const _BulkMoveSheet({
    required this.selectedIds,
    required this.mine,
    required this.onPick,
    required this.onCreateNew,
  });

  final Set<String> selectedIds;
  final List<Item> mine;
  final Future<void> Function(Bucket? destination) onPick;
  final Future<void> Function(String name, List<Bucket> allBuckets) onCreateNew;

  void _showNewListDialog(BuildContext ctx, List<Bucket> allBuckets) {
    final controller = TextEditingController();
    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: DotColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'New list',
          style: DotText.font(size: 16.5, weight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: DotText.font(size: 14.5, weight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'List name',
            hintStyle: DotText.font(
                size: 14.5, weight: FontWeight.w500, color: DotColors.faint2),
            filled: true,
            fillColor: DotColors.searchFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DotColors.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DotColors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: brandRed.withValues(alpha: 0.5), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: DotText.font(
                  size: 14, weight: FontWeight.w600, color: DotColors.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogCtx).pop();
              onCreateNew(name, allBuckets);
            },
            child: Text(
              'Create & Move',
              style: DotText.font(
                  size: 14, weight: FontWeight.w700, color: DotColors.inkStrong),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(bucketsProvider);
    final allBuckets = bucketsAsync.asData?.value ?? const [];

    return Container(
      decoration: const BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DotRadii.sheetTop),
        ),
        boxShadow: DotShadow.sheet,
      ),
      padding: EdgeInsets.fromLTRB(
          0, 0, 0, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grabber
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DotColors.grabber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Text(
              'Move ${selectedIds.length} item${selectedIds.length == 1 ? '' : 's'} to…',
              style: DotText.font(size: 17, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // + New list row
                  InkWell(
                    onTap: () => _showNewListDialog(context, allBuckets),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: DotColors.faint2, width: 1.5),
                            ),
                            child: Center(
                              child: Icon(Icons.add,
                                  size: 10, color: DotColors.faint2),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '+ New list',
                            style: DotText.font(
                                size: 15.5,
                                weight: FontWeight.w600,
                                color: DotColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Unsorted option
                  _BulkBucketRow(
                    label: 'Unsorted',
                    colorKey: 'unsorted',
                    onTap: () => onPick(null),
                  ),
                  // All buckets
                  for (final b in allBuckets)
                    _BulkBucketRow(
                      label: b.name,
                      colorKey: b.colorKey,
                      onTap: () => onPick(b),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _BulkBucketRow extends StatelessWidget {
  const _BulkBucketRow({
    required this.label,
    required this.colorKey,
    required this.onTap,
  });

  final String label;
  final String colorKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = bucketColorsFor(colorKey);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: DotText.font(
                  size: 15.5,
                  weight: FontWeight.w600,
                  color: DotColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
