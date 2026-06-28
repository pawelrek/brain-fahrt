import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../core/widgets/dot_icon.dart';
import '../../core/widgets/red_dot.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../capture/capture_controller.dart';
import '../settings/settings_screen.dart';
import 'bucket_actions.dart';
import 'bucket_card.dart';
import 'capture_fab.dart';
import 'create_bucket_sheet.dart';

/// App version (real pubspec version), loaded once for the header label.
final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

/// The Google-Keep-style board screen.
///
/// Shows a 2-column masonry grid of [BucketCard]s with [UnsortedCard] spliced
/// at index 2 when there are unsorted items. A [CaptureFab] floats at the
/// bottom.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenBucket,
    required this.onCapture,
  });

  final void Function(String bucketId) onOpenBucket;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets =
        ref.watch(bucketsProvider).asData?.value ?? const <Bucket>[];
    final items =
        ref.watch(itemsProvider).asData?.value ?? const <Item>[];
    final newItemId = ref.watch(newItemIdProvider); // String?
    // Force-create the capture pipeline at startup so its eager model warmup
    // kicks off now (Qwen loads in the background) instead of stalling the first
    // capture — the dashboard is the home screen, so this runs on launch.
    ref.read(capturePipelineProvider);

    // Group items by bucketId; null → unsorted.
    final Map<String, List<Item>> byBucket = {};
    final List<Item> unsortedItems = [];

    for (final b in buckets) {
      byBucket[b.id] = [];
    }
    for (final item in items) {
      final bid = item.bucketId;
      if (bid != null && byBucket.containsKey(bid)) {
        byBucket[bid]!.add(item);
      } else {
        unsortedItems.add(item);
      }
    }

    // Determine which bucket has the new item (for the ring overlay).
    String? newBucketId;
    if (newItemId != null) {
      final match = items.where((i) => i.id == newItemId).firstOrNull;
      newBucketId = match?.bucketId ?? 'unsorted';
    }

    // Build card widgets in bucket order.
    final List<Widget> cards = [
      for (final b in buckets)
        BucketCard(
          key: ValueKey(b.id),
          bucket: b,
          items: byBucket[b.id] ?? const [],
          colors: bucketColorsFor(b.colorKey),
          isNew: newBucketId == b.id,
          newItemId: newItemId,
          onOpen: () {
            AppLog.instance.log('ui', 'opened bucket ${b.id}');
            onOpenBucket(b.id);
          },
          onLongPress: () {
            AppLog.instance.log('ui', 'long-pressed bucket ${b.id}');
            showBucketActions(context, ref, b);
          },
        ),
    ];

    // Splice UnsortedCard at index 2 when there are unsorted items.
    if (unsortedItems.isNotEmpty) {
      final unsortedCard = UnsortedCard(
        key: const ValueKey('unsorted'),
        items: unsortedItems,
        isNew: newBucketId == 'unsorted',
        newItemId: newItemId,
        onOpen: () => onOpenBucket('unsorted'),
      );
      final insertAt = cards.length >= 2 ? 2 : cards.length;
      cards.insert(insertAt, unsortedCard);
    }

    return ColoredBox(
      color: DotColors.canvas,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
          children: [
            // Header.
            Padding(
              padding: DotPad.header,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const RedDot(size: 24, ringWeight: 3),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text('brain-fahrt',
                                  style: DotText.wordmark,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 7),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: FutureBuilder<PackageInfo>(
                                future: _packageInfo,
                                builder: (_, snap) => Text(
                                  snap.hasData ? 'v${snap.data!.version}' : '',
                                  style: DotText.font(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: DotColors.faint2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Add-list button.
                      GestureDetector(
                        onTap: () {
                          AppLog.instance
                              .log('ui', 'create-list button tapped');
                          showCreateBucketSheet(context, ref);
                        },
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Icon(
                              Icons.add,
                              size: 24,
                              color: DotColors.muted,
                            ),
                          ),
                        ),
                      ),
                      // Settings button.
                      GestureDetector(
                        onTap: () {
                          AppLog.instance.log('ui', 'opened settings');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Icon(
                              Icons.settings,
                              size: 22,
                              color: DotColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Demo-mode banner — shown when on-device models are absent.
                  Consumer(
                    builder: (context, ref, _) {
                      if (ref.watch(usingRealPipelineProvider)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: DotColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: DotColors.outline),
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
                                  'Demo mode — on-device AI models not found. Captures are simulated.',
                                  style: DotText.font(
                                    size: 11.5,
                                    weight: FontWeight.w500,
                                    color: DotColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Model-load progress — shows until the LLM is loaded + warm.
                  // Only relevant when the real pipeline is active (in demo mode
                  // modelReadyProvider never resolves, so the bar never completes).
                  Consumer(
                    builder: (context, ref, _) {
                      if (!ref.watch(usingRealPipelineProvider)) {
                        return const SizedBox.shrink();
                      }
                      if (ref.watch(modelReadyProvider)) {
                        return const SizedBox.shrink();
                      }
                      // Staged 0→100% progress fed by real pipeline events
                      // (Whisper load → LLM load % → warm-up). Informational,
                      // not a gate: capture works the moment the app is up
                      // (mic + Whisper only) — notes file right after
                      // transcription and the sorting patch catches up when
                      // the LLM is warm, so every label keeps that visible.
                      final sp = ref.watch(startupProgressProvider);
                      final label = sp.label.isEmpty
                          ? 'AI warming up — capture anytime, sorting catches up…'
                          : '${sp.label} — capture anytime';
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: DotText.font(
                                size: 11.5,
                                weight: FontWeight.w600,
                                color: DotColors.muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: sp.value,
                                minHeight: 4,
                                backgroundColor: DotColors.hairline,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(brandRed),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Search field.
                  Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 11),
                      decoration: BoxDecoration(
                        // Keep-dark "Search Keep" pill: flat fill, no border.
                        color: DotColors.searchFill,
                        borderRadius:
                            BorderRadius.circular(DotRadii.search),
                      ),
                      child: Row(
                        children: [
                          DotIcon(
                            DotIconName.search,
                            size: 19,
                            color: DotColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Search your thoughts',
                            style: DotText.searchPlaceholder,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Board.
            Expanded(
              child: MasonryGridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                padding: DotPad.board,
                itemCount: cards.length,
                itemBuilder: (_, i) => cards[i],
              ),
            ),
          ],
        ),
        // Floating capture button.
        CaptureFab(onCapture: onCapture),
          ],
        ),
      ),
    );
  }
}

