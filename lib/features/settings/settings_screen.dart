/// Settings screen — persisted options: model, font size, optimistic loading,
/// greedy decoding. Matches the DotColors/DotText/DotPad design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../data/model_download_provider.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../../pipeline/real/model_registry.dart';
import '../../pipeline/real/stt_registry.dart';
import '../logs/logs_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(fontSizeProvider);
    final optimisticLoading = ref.watch(optimisticLoadingProvider);
    final greedyDecoding = ref.watch(greedyDecodingProvider);

    return ColoredBox(
      color: DotColors.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: DotPad.header,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Icon(
                          Icons.chevron_left,
                          size: 26,
                          color: DotColors.muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Settings', style: DotText.wordmark),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // ── Model ───────────────────────────────────────────────────
                  _SectionLabel(label: 'Model'),
                  const SizedBox(height: 8),
                  for (final m in LlmModel.values)
                    _ModelRow(model: m),
                  const SizedBox(height: 6),
                  Text(
                    'Switching reloads the model (a few seconds). '
                    'Locked models must be downloaded first.',
                    style: DotText.font(
                      size: 12,
                      color: DotColors.faint2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── Speech recognition (STT) ────────────────────────────────
                  _SectionLabel(label: 'Speech recognition'),
                  const SizedBox(height: 8),
                  for (final m in SttModel.values) _SttModelRow(model: m),
                  const SizedBox(height: 6),
                  Text(
                    'The voice-to-text model. Multilingual is more forgiving of '
                    'accents; English-only is tuned for native English. '
                    'Switching reloads the recognizer (~1–2s).',
                    style: DotText.font(
                      size: 12,
                      color: DotColors.faint2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── Font size ───────────────────────────────────────────────
                  _SectionLabel(label: 'Font size'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _SegmentedControl<FontSize>(
                        options: const [
                          (FontSize.small, 'Small'),
                          (FontSize.medium, 'Medium'),
                          (FontSize.large, 'Large'),
                        ],
                        selected: fontSize,
                        onSelect: (size) {
                          AppLog.instance
                              .log('ui', 'setting fontSize=${size.name}');
                          ref.read(fontSizeProvider.notifier).set(size);
                        },
                        isDisabled: (_) => false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ── Optimistic loading ──────────────────────────────────────
                  _SectionLabel(label: 'Optimistic loading'),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'On: the AI loads when you open the app (faster first sort). '
                          'Off: it loads in the background on your first capture — '
                          'the note files right after transcription either way; '
                          'sorting may just take a little longer to catch up.',
                          style: DotText.font(
                            size: 13,
                            color: DotColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Switch(
                        value: optimisticLoading,
                        onChanged: (v) {
                          AppLog.instance
                              .log('ui', 'setting optimisticLoading=$v');
                          ref.read(optimisticLoadingProvider.notifier).set(v);
                        },
                        activeThumbColor: DotColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ── Model behaviour ─────────────────────────────────────────
                  _SectionLabel(label: 'Model behaviour'),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    title: 'Greedy decoding',
                    subtitle: 'Faster, deterministic routing',
                    value: greedyDecoding,
                    onChanged: (v) {
                      AppLog.instance.log('ui', 'setting greedyDecoding=$v');
                      ref.read(greedyDecodingProvider.notifier).set(v);
                    },
                  ),
                  const SizedBox(height: 24),
                  // ── Logs ────────────────────────────────────────────────────
                  _SectionLabel(label: 'Debug'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LogsScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: DotColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: DotShadow.search,
                        border: Border.all(color: DotColors.outline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Logs',
                              style: DotText.font(
                                size: 15,
                                weight: FontWeight.w600,
                                color: DotColors.ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: DotColors.faint2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: DotText.font(
        size: 11,
        weight: FontWeight.w700,
        color: DotColors.faint2,
        letterSpacing: 0.6,
      ),
    );
  }
}

// ── Model row ─────────────────────────────────────────────────────────────────

class _ModelRow extends ConsumerWidget {
  const _ModelRow({required this.model});

  final LlmModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedModelProvider) == model;
    final dlState =
        ref.watch(modelManagerProvider.select((m) => m[model])) ??
            const ModelAbsent();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: DotShadow.search,
        border: Border.all(
          color: selected ? DotColors.muted : DotColors.outline,
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: switch (dlState) {
        ModelPresent() => _PresentRow(model: model, selected: selected),
        ModelAbsent() => _AbsentRow(model: model),
        ModelDownloading() => _DownloadingRow(model: model, dlState: dlState),
        ModelDownloadFailed() => _FailedRow(model: model, dlState: dlState),
      },
    );
  }
}

// ── ModelPresent row (tappable, selection + checkmark) ────────────────────────

class _PresentRow extends ConsumerWidget {
  const _PresentRow({required this.model, required this.selected});

  final LlmModel model;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        if (selected) return;
        AppLog.instance.log('ui', 'model -> ${model.name}');
        ref.read(selectedModelProvider.notifier).set(model);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                model.label,
                style: DotText.font(
                  size: 15,
                  weight: FontWeight.w600,
                  color: DotColors.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: DotColors.muted),
          ],
        ),
      ),
    );
  }
}

// ── STT (Whisper) model row — both variants present, tappable selection ──────

class _SttModelRow extends ConsumerWidget {
  const _SttModelRow({required this.model});

  final SttModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSttModelProvider) == model;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: DotShadow.search,
        border: Border.all(
          color: selected ? DotColors.muted : DotColors.outline,
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          if (selected) return;
          AppLog.instance.log('ui', 'stt -> ${model.name}');
          ref.read(selectedSttModelProvider.notifier).set(model);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.label,
                      style: DotText.font(
                        size: 15,
                        weight: FontWeight.w600,
                        color: DotColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.sublabel,
                      style: DotText.font(size: 12, color: DotColors.muted),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check, size: 18, color: DotColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ModelAbsent row (dimmed label, size, download button) ────────────────────

class _AbsentRow extends ConsumerWidget {
  const _AbsentRow({required this.model});

  final LlmModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeLabel = model.sizeBytes != null
        ? '${(model.sizeBytes! / 1e9).toStringAsFixed(1)} GB'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.label,
                  style: DotText.font(
                    size: 15,
                    weight: FontWeight.w600,
                    color: DotColors.faint2,
                  ),
                ),
                if (sizeLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sizeLabel,
                    style: DotText.font(size: 12, color: DotColors.faint3),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined,
                size: 20, color: DotColors.muted),
            onPressed: () => ref
                .read(modelManagerProvider.notifier)
                .startDownload(model),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── ModelDownloading row (progress bar + percent + cancel) ───────────────────

class _DownloadingRow extends ConsumerWidget {
  const _DownloadingRow({required this.model, required this.dlState});

  final LlmModel model;
  final ModelDownloading dlState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTotal = dlState.total > 0;
    final pct = hasTotal ? '${(dlState.progress * 100).round()}%' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.label,
                        style: DotText.font(
                          size: 15,
                          weight: FontWeight.w600,
                          color: DotColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      pct,
                      style:
                          DotText.font(size: 12, color: DotColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: hasTotal ? dlState.progress : null,
                    minHeight: 4,
                    backgroundColor: DotColors.hairline,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(brandRed),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: DotColors.muted),
            onPressed: () =>
                ref.read(modelManagerProvider.notifier).cancel(model),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── ModelDownloadFailed row (error message + retry / metered confirm) ─────────

class _FailedRow extends ConsumerWidget {
  const _FailedRow({required this.model, required this.dlState});

  final LlmModel model;
  final ModelDownloadFailed dlState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.label,
                  style: DotText.font(
                    size: 15,
                    weight: FontWeight.w600,
                    color: DotColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dlState.isMetered
                      ? 'No Wi-Fi — download on mobile data?'
                      : dlState.message,
                  style: DotText.font(
                    size: 12,
                    color: dlState.isMetered
                        ? DotColors.muted
                        : const Color(0xFFE57373),
                  ),
                ),
              ],
            ),
          ),
          if (dlState.isMetered) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref
                  .read(modelManagerProvider.notifier)
                  .startDownload(model, allowMetered: true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: DotColors.searchFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Download',
                  style: DotText.font(
                    size: 13,
                    weight: FontWeight.w600,
                    color: DotColors.muted,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh,
                  size: 20, color: DotColors.muted),
              onPressed: () => ref
                  .read(modelManagerProvider.notifier)
                  .startDownload(model),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.isDisabled,
  });

  final List<(T, String)> options;
  final T selected;
  final void Function(T) onSelect;
  final bool Function(T) isDisabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: DotColors.grabber,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            _SettingsSegment(
              label: label,
              active: selected == value,
              onTap: isDisabled(value) ? null : () => onSelect(value),
            ),
        ],
      ),
    );
  }
}

class _SettingsSegment extends StatelessWidget {
  const _SettingsSegment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 32,
        decoration: BoxDecoration(
          color: active ? DotColors.muted : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: DotText.font(
            size: 13,
            weight: FontWeight.w600,
            // Active segment: dark label on the light (muted) fill.
            color: active
                ? DotColors.canvas
                : (disabled ? DotColors.faint3 : DotColors.muted),
          ),
        ),
      ),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: DotText.font(
                  size: 15,
                  weight: FontWeight.w600,
                  color: DotColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: DotText.font(
                  size: 13,
                  color: DotColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: DotColors.muted,
        ),
      ],
    );
  }
}
