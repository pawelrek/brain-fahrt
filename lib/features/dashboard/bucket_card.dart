import 'package:flutter/widgets.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/dot_icon.dart';
import '../../core/widgets/type_glyph.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';

/// Max preview rows on a card face before the '+N more' line.
const int _kPreviewCap = 6;

// ---------------------------------------------------------------------------
// BucketCard — neutral (Keep-dark) card for a named bucket.
// ---------------------------------------------------------------------------

/// A neutral surface card showing up to [_kPreviewCap] item previews.
/// The bucket's color survives as a 10px dot before the name and as the
/// tint on checkbox/type glyphs + the count text.
///
/// [isNew] triggers a one-shot accent ring overlay (~1.6s).
/// [newItemId] bolds the matching preview row.
class BucketCard extends StatefulWidget {
  const BucketCard({
    super.key,
    required this.bucket,
    required this.items,
    required this.colors,
    required this.onOpen,
    this.isNew = false,
    this.newItemId,
    this.onLongPress,
  });

  final Bucket bucket;
  final List<Item> items;
  final BucketColors colors;
  final VoidCallback onOpen;

  /// True when this bucket contains the most-recently-captured item.
  final bool isNew;

  /// The id of the item to highlight (bold) in the preview list.
  final String? newItemId;

  /// Optional long-press handler (e.g. open rename/delete actions sheet).
  final VoidCallback? onLongPress;

  @override
  State<BucketCard> createState() => _BucketCardState();
}

class _BucketCardState extends State<BucketCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isList = widget.bucket.shape == BucketShape.list;
    final colors = widget.colors;
    const previewCount = _kPreviewCap;

    // Sort descending by createdAt, then slice.
    final sorted = [...widget.items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final previews = sorted.take(previewCount).toList();

    final openCount = isList
        ? widget.items.where((i) => !i.done).length
        : widget.items.length;
    final countText = isList
        ? '$openCount left'
        : (widget.items.length == 1 ? '1 note' : '${widget.items.length} notes');

    final noAnim = MediaQuery.of(context).disableAnimations;

    // New-item ring overlay.
    Widget? ringOverlay;
    if (widget.isNew && !noAnim) {
      ringOverlay = TweenAnimationBuilder<double>(
        key: ValueKey(widget.newItemId),
        tween: Tween(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 1600),
        curve: Curves.easeOut,
        builder: (_, value, _) => Opacity(
          opacity: value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DotRadii.card),
              border: Border.all(
                color: colors.accent,
                width: 2,
              ),
            ),
          ),
        ),
      );
    }

    Widget card = Container(
      decoration: BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.circular(DotRadii.card),
        border: Border.all(color: DotColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: color dot + name + plain muted count text.
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.bucket.name,
                    style: DotText.cardName.copyWith(color: DotColors.inkTitle),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  countText,
                  style: DotText.font(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            // Preview rows.
            if (widget.items.isEmpty)
              Text(
                'Empty — say a thought',
                style: DotText.font(
                  size: 13,
                  color: colors.ink.withValues(alpha: 0.5),
                ).copyWith(fontStyle: FontStyle.italic),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < previews.length; i++) ...[
                    if (i > 0) SizedBox(height: isList ? 7 : 9),
                    _PreviewRow(
                      item: previews[i],
                      isList: isList,
                      colors: colors,
                      isHighlighted: previews[i].id == widget.newItemId,
                    ),
                  ],
                ],
              ),
            // "+N more"
            if (widget.items.length > previewCount)
              Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Text(
                  '+${widget.items.length - previewCount} more',
                  style: DotText.font(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: DotColors.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Wrap in a Stack if we have a ring overlay.
    if (ringOverlay != null) {
      card = Stack(
        children: [
          card,
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ringOverlay,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onOpen();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: const Cubic(0.2, 0.7, 0.3, 1),
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview row — used inside BucketCard.
// ---------------------------------------------------------------------------

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.item,
    required this.isList,
    required this.colors,
    required this.isHighlighted,
  });

  final Item item;
  final bool isList;
  final BucketColors colors;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    if (isList) {
      return _ListPreviewRow(
        item: item,
        colors: colors,
        isHighlighted: isHighlighted,
      );
    }
    return _ProjectPreviewRow(
      item: item,
      colors: colors,
      isHighlighted: isHighlighted,
    );
  }
}

class _ProjectPreviewRow extends StatelessWidget {
  const _ProjectPreviewRow({
    required this.item,
    required this.colors,
    required this.isHighlighted,
  });

  final Item item;
  final BucketColors colors;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final glyph = item.type != null
        ? TypeGlyph(
            type: item.type!,
            size: 13,
            color: colors.accent.withValues(alpha: 0.7),
          )
        : const SizedBox(width: 13, height: 13);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.5),
          child: glyph,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DotText.itemSummary.copyWith(
              color: DotColors.inkBody,
              fontWeight:
                  isHighlighted ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ListPreviewRow extends StatelessWidget {
  const _ListPreviewRow({
    required this.item,
    required this.colors,
    required this.isHighlighted,
  });

  final Item item;
  final BucketColors colors;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final done = item.done;

    // Keep-style square outline checkbox (filled accent + canvas check when done).
    final checkbox = Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: done
            ? null
            : Border.all(
                color: colors.accent.withValues(alpha: 0.55),
                width: 1.5,
              ),
        color: done ? colors.accent : null,
      ),
      child: done
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: checkbox,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Opacity(
            opacity: done ? 0.5 : 1.0,
            child: Text(
              item.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DotText.itemSummary.copyWith(
                color: DotColors.inkBody,
                fontWeight:
                    isHighlighted ? FontWeight.w700 : FontWeight.w500,
                decoration:
                    done ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UnsortedCard — neutral card for items with no bucket.
// ---------------------------------------------------------------------------

/// Card shown for items with `bucketId == null`.
///
/// Same neutral face as [BucketCard]: up to [_kPreviewCap] preview rows with
/// an accent dot, a '+N more' line when truncated, and a footer CTA.
class UnsortedCard extends StatefulWidget {
  const UnsortedCard({
    super.key,
    required this.items,
    required this.onOpen,
    this.isNew = false,
    this.newItemId,
  });

  final List<Item> items;
  final VoidCallback onOpen;

  /// True when a low-confidence capture just landed in Unsorted (fires the ring).
  final bool isNew;
  final String? newItemId;

  @override
  State<UnsortedCard> createState() => _UnsortedCardState();
}

class _UnsortedCardState extends State<UnsortedCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = bucketColorsFor('unsorted');

    // Sort descending by createdAt, then slice.
    final sorted = [...widget.items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final previews = sorted.take(_kPreviewCap).toList();

    final card = Container(
      decoration: BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.circular(DotRadii.card),
        border: Border.all(color: DotColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row.
            Row(
              children: [
                DotIcon(
                  DotIconName.inbox,
                  size: 17,
                  color: colors.accent,
                  weight: 1.9,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Unsorted',
                    style: DotText.cardName.copyWith(color: DotColors.inkTitle),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.items.length}',
                  style: DotText.font(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
            if (previews.isNotEmpty) ...[
              const SizedBox(height: 11),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < previews.length; i++) ...[
                    if (i > 0) const SizedBox(height: 9),
                    _UnsortedPreviewRow(
                      item: previews[i],
                      colors: colors,
                      isHighlighted:
                          previews[i].id == widget.newItemId,
                    ),
                  ],
                ],
              ),
            ],
            // "+N more"
            if (widget.items.length > _kPreviewCap)
              Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Text(
                  '+${widget.items.length - _kPreviewCap} more',
                  style: DotText.font(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: DotColors.muted,
                  ),
                ),
              ),
            // Footer CTA.
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Tap to file these →',
                style: DotText.font(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget content = card;
    if (widget.isNew && !MediaQuery.of(context).disableAnimations) {
      content = Stack(
        children: [
          card,
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(widget.newItemId),
                tween: Tween(begin: 1.0, end: 0.0),
                duration: const Duration(milliseconds: 1600),
                curve: Curves.easeOut,
                builder: (_, value, _) => Opacity(
                  opacity: value,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(DotRadii.card),
                      border: Border.all(color: colors.accent, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onOpen();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: const Cubic(0.2, 0.7, 0.3, 1),
        child: content,
      ),
    );
  }
}

class _UnsortedPreviewRow extends StatelessWidget {
  const _UnsortedPreviewRow({
    required this.item,
    required this.colors,
    required this.isHighlighted,
  });

  final Item item;
  final BucketColors colors;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 13px-wide leading slot — same geometry as the glyph/checkbox rows.
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SizedBox(
            width: 13,
            height: 13,
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DotText.itemSummary.copyWith(
              color: DotColors.inkBody,
              fontWeight:
                  isHighlighted ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
