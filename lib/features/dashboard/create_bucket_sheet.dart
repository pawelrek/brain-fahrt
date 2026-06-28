import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../core/util/id.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

Future<void> showCreateBucketSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreateBucketSheet(ref: ref),
  );
}

// The six selectable palette keys in display order.
const List<String> _colorKeys = [
  'devhub',
  'webapp',
  'general',
  'shopping',
  'todos',
  'ideas',
];

class _CreateBucketSheet extends StatefulWidget {
  const _CreateBucketSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_CreateBucketSheet> createState() => _CreateBucketSheetState();
}

class _CreateBucketSheetState extends State<_CreateBucketSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _kwController = TextEditingController();
  BucketShape _shape = BucketShape.list;
  String _colorKey = 'todos';
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _kwController.dispose();
    super.dispose();
  }

  bool get _canCreate => _nameController.text.trim().isNotEmpty;

  Future<void> _onCreate() async {
    if (_creating) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    AppLog.instance
        .log('ui', 'created bucket name="$name" shape=${_shape.name}');
    try {
      await widget.ref.read(databaseProvider).insertBucket(
            id: newId('b'),
            name: name,
            shape: _shape,
            colorKey: _colorKey,
            description: _descController.text.trim(),
            keywords: _kwController.text.trim(),
          );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DotRadii.sheetTop),
        ),
        boxShadow: DotShadow.sheet,
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grabber.
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
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
          // Title.
          Text(
            'New list',
            style: DotText.font(size: 19, weight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          // Name field.
          TextField(
            controller: _nameController,
            autofocus: true,
            style: DotText.font(size: 15, weight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'List name',
              hintStyle: DotText.font(
                  size: 15,
                  weight: FontWeight.w500,
                  color: DotColors.faint2),
              filled: true,
              fillColor: DotColors.searchFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: DotColors.hairline, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: DotColors.hairline, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: brandRed.withValues(alpha: 0.5), width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: _canCreate ? (_) => _onCreate() : null,
          ),
          const SizedBox(height: 12),
          // Description field.
          TextField(
            controller: _descController,
            style: DotText.font(size: 15, weight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'What is this list for?',
              hintStyle: DotText.font(
                  size: 15,
                  weight: FontWeight.w500,
                  color: DotColors.faint2),
              filled: true,
              fillColor: DotColors.searchFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: DotColors.hairline, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: DotColors.hairline, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: brandRed.withValues(alpha: 0.5), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Keywords field.
          TextField(
            controller: _kwController,
            style: DotText.font(size: 15, weight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'comma-separated, e.g. login, signup, crash',
              hintStyle: DotText.font(
                  size: 15,
                  weight: FontWeight.w500,
                  color: DotColors.faint2),
              filled: true,
              fillColor: DotColors.searchFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: DotColors.hairline, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: DotColors.hairline, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: brandRed.withValues(alpha: 0.5), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Shape selector.
          Row(
            children: [
              _ShapePill(
                label: 'Project',
                selected: _shape == BucketShape.project,
                onTap: () => setState(() => _shape = BucketShape.project),
              ),
              const SizedBox(width: 10),
              _ShapePill(
                label: 'Simple list',
                selected: _shape == BucketShape.list,
                onTap: () => setState(() => _shape = BucketShape.list),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Color swatches.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final key in _colorKeys)
                _ColorSwatch(
                  colorKey: key,
                  selected: _colorKey == key,
                  onTap: () => setState(() => _colorKey = key),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Create button.
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _canCreate ? _onCreate : null,
              child: AnimatedOpacity(
                opacity: _canCreate ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: DotColors.ink,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: _canCreate ? DotShadow.stopButton : null,
                  ),
                  child: Text(
                    'Create',
                    style: DotText.font(
                      size: 15.5,
                      weight: FontWeight.w700,
                      // Dark label on the light (ink-filled) pill.
                      color: DotColors.canvas,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShapePill extends StatelessWidget {
  const _ShapePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? null
              : Border.all(color: DotColors.outline, width: 1.2),
        ),
        child: Text(
          label,
          style: DotText.font(
            size: 13.5,
            weight: FontWeight.w600,
            color: selected ? DotColors.white : DotColors.ink,
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.colorKey,
    required this.selected,
    required this.onTap,
  });

  final String colorKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = bucketColorsFor(colorKey).accent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          border: selected
              ? Border.all(color: DotColors.ink, width: 2)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
      ),
    );
  }
}
