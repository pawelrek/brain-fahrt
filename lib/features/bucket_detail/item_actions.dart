import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Shows a bottom-sheet with Edit / Move to… / Delete actions for [item].
///
/// Call from any widget that has a [BuildContext] and a [WidgetRef].
void showItemActions(BuildContext context, WidgetRef ref, Item item) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: DotColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DotRadii.sheetTop),
      ),
    ),
    builder: (sheetCtx) => _ItemActionsSheet(
      item: item,
      onEdit: () {
        AppLog.instance.log('ui', 'edit item ${item.id}');
        Navigator.of(sheetCtx).pop();
        showEditItemDialog(context, ref, item);
      },
      onMoveTo: () {
        AppLog.instance.log('ui', 'move item ${item.id} tapped');
        Navigator.of(sheetCtx).pop();
        _showBucketPicker(context, item);
      },
      onDelete: () async {
        // [13] Close the actions sheet first, then confirm before deleting.
        Navigator.of(sheetCtx).pop();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: DotColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Delete item?',
              style: DotText.font(size: 16.5, weight: FontWeight.w700),
            ),
            content: Text(
              item.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DotText.font(
                size: 14,
                weight: FontWeight.w500,
                color: DotColors.muted,
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(
                  'Cancel',
                  style: DotText.font(
                    size: 14,
                    weight: FontWeight.w600,
                    color: DotColors.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(
                  'Delete',
                  style: DotText.font(
                    size: 14,
                    weight: FontWeight.w700,
                    color: DotReds.classic,
                  ),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        AppLog.instance.log('ui', 'delete item ${item.id}');
        try {
          await ref.read(databaseProvider).deleteItem(item.id);
        } catch (e, st) {
          AppLog.instance.log('error', 'deleteItem failed: $e\n$st');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not delete item.')),
            );
          }
        }
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Actions sheet content
// ---------------------------------------------------------------------------

class _ItemActionsSheet extends StatelessWidget {
  const _ItemActionsSheet({
    required this.item,
    required this.onEdit,
    required this.onMoveTo,
    required this.onDelete,
  });

  final Item item;
  final VoidCallback onEdit;
  final VoidCallback onMoveTo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber pill
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: DotColors.grabber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Item preview (truncated)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                item.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DotText.font(
                  size: 13.5,
                  weight: FontWeight.w500,
                  color: DotColors.muted,
                ),
              ),
            ),
            // Divider
            Container(
              height: 1,
              color: DotColors.hairline,
              margin: const EdgeInsets.only(bottom: 6),
            ),
            // Edit row
            _ActionTile(
              icon: Icons.edit_outlined,
              label: 'Edit',
              color: DotColors.ink,
              onTap: onEdit,
            ),
            // Move to… row
            _ActionTile(
              icon: Icons.drive_file_move_outline,
              label: 'Move to…',
              color: DotColors.ink,
              onTap: onMoveTo,
            ),
            // Delete row
            _ActionTile(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: DotReds.classic,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: DotText.font(
                size: 15,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bucket picker sheet
// ---------------------------------------------------------------------------

void _showBucketPicker(BuildContext context, Item item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BucketPickerSheet(item: item),
  );
}

class _BucketPickerSheet extends ConsumerWidget {
  const _BucketPickerSheet({required this.item});

  final Item item;

  Future<void> _pick(BuildContext ctx, WidgetRef ref, Bucket? bucket) async {
    // [12] No-op if user picked the item's current bucket — just close the sheet.
    if ((bucket == null && item.bucketId == null) ||
        (bucket != null && bucket.id == item.bucketId)) {
      if (ctx.mounted) Navigator.of(ctx).pop();
      return;
    }

    AppLog.instance
        .log('ui', 'moved item ${item.id} -> ${bucket?.id ?? 'unsorted'}');
    final db = ref.read(databaseProvider);
    if (bucket == null) {
      // Unsorted
      await db.moveItemToBucket(item.id, null, type: null);
      if (item.bucketId != null) {
        await db.insertCorrection(item.summary, 'unsorted');
      }
    } else if (bucket.shape == BucketShape.list) {
      await db.moveItemToBucket(item.id, bucket.id, type: null);
      if (item.bucketId != bucket.id) {
        await db.insertCorrection(item.summary, bucket.id);
      }
    } else {
      // project bucket — preserve or default type
      final t = item.type ?? ItemType.improvement;
      await db.moveItemToBucket(item.id, bucket.id, type: t);
      if (item.bucketId != bucket.id) {
        await db.insertCorrection(item.summary, bucket.id);
      }
    }
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(bucketsProvider);

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
              'Move to…',
              style: DotText.font(size: 17, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          // [14] Constrain list height so many buckets don't cause RenderFlex
          // overflow in the isScrollControlled bottom sheet.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Unsorted option
                  _BucketPickerRow(
                    label: 'Unsorted',
                    colorKey: 'unsorted',
                    isCurrent: item.bucketId == null,
                    onTap: () => _pick(context, ref, null),
                  ),
                  bucketsAsync.when(
                    data: (buckets) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final b in buckets)
                          _BucketPickerRow(
                            label: b.name,
                            colorKey: b.colorKey,
                            isCurrent: item.bucketId == b.id,
                            onTap: () => _pick(context, ref, b),
                          ),
                      ],
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
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

class _BucketPickerRow extends StatelessWidget {
  const _BucketPickerRow({
    required this.label,
    required this.colorKey,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final String colorKey;
  final bool isCurrent;
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
            if (isCurrent)
              Icon(Icons.check_rounded, size: 18, color: colors.accent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit dialog
// ---------------------------------------------------------------------------

void showEditItemDialog(BuildContext context, WidgetRef ref, Item item) {
  final controller = TextEditingController(text: item.summary);

  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: DotColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        'Edit',
        style: DotText.font(size: 16.5, weight: FontWeight.w700),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: DotText.font(size: 14.5, weight: FontWeight.w500),
        decoration: InputDecoration(
          filled: true,
          fillColor: DotColors.searchFill,
          hintText: 'Summary…',
          hintStyle: DotText.font(
            size: 14.5,
            weight: FontWeight.w500,
            color: DotColors.faint2,
          ),
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
            borderSide: BorderSide(
                color: brandRed.withValues(alpha: 0.5), width: 1.5),
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
              size: 14,
              weight: FontWeight.w600,
              color: DotColors.muted,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            final newText = controller.text.trim();
            if (newText.isNotEmpty) {
              await ref.read(databaseProvider).updateItemSummary(item.id, newText);
            }
            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
          },
          child: Text(
            'Save',
            style: DotText.font(
              size: 14,
              weight: FontWeight.w700,
              color: DotColors.inkStrong,
            ),
          ),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
