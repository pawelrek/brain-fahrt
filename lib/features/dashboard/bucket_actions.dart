import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';

Future<void> showBucketActions(
    BuildContext context, WidgetRef ref, Bucket bucket) {
  // Capture the outer (dashboard) context before opening the sheet so it can
  // be used for follow-up dialogs after the sheet route is popped.
  final callerContext = context;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _BucketActionsSheet(
      sheetCtx: sheetCtx,
      callerContext: callerContext,
      ref: ref,
      bucket: bucket,
    ),
  );
}

class _BucketActionsSheet extends StatelessWidget {
  const _BucketActionsSheet({
    required this.sheetCtx,
    required this.callerContext,
    required this.ref,
    required this.bucket,
  });

  final BuildContext sheetCtx;
  // The outer context (dashboard), guaranteed to stay mounted after the sheet
  // is popped. Used for showDialog calls that follow Navigator.pop().
  final BuildContext callerContext;
  final WidgetRef ref;
  final Bucket bucket;

  void _edit() {
    AppLog.instance.log('ui', 'edit bucket ${bucket.id}');
    Navigator.of(sheetCtx).pop();
    showDialog<void>(
      context: callerContext,
      builder: (_) => _EditDialog(ref: ref, bucket: bucket),
    );
  }

  void _delete() {
    AppLog.instance.log('ui', 'delete bucket ${bucket.id}');
    Navigator.of(sheetCtx).pop();
    showDialog<void>(
      context: callerContext,
      builder: (_) => _DeleteDialog(ref: ref, bucket: bucket),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DotRadii.sheetTop),
        ),
        boxShadow: DotShadow.sheet,
      ),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grabber.
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
          // Bucket name header.
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                bucket.name,
                style: DotText.font(
                  size: 13,
                  weight: FontWeight.w600,
                  color: DotColors.faint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Edit row.
          _ActionRow(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: DotColors.ink,
            onTap: _edit,
          ),
          // Delete row.
          _ActionRow(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: DotReds.classic,
            onTap: _delete,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: DotText.font(
                size: 15.5,
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
// Edit dialog (name + description + keywords)
// ---------------------------------------------------------------------------

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.ref, required this.bucket});

  final WidgetRef ref;
  final Bucket bucket;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.bucket.name);
  late final TextEditingController _descCtrl =
      TextEditingController(text: widget.bucket.description);
  late final TextEditingController _kwCtrl =
      TextEditingController(text: widget.bucket.keywords);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _kwCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    AppLog.instance.log('ui', 'saved bucket edit ${widget.bucket.id}');
    await widget.ref.read(databaseProvider).updateBucketMeta(
          widget.bucket.id,
          name: name,
          description: _descCtrl.text.trim(),
          keywords: _kwCtrl.text.trim(),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(TextEditingController ctrl, String hint,
      {bool autofocus = false}) {
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      style: DotText.font(size: 15, weight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: DotText.font(
            size: 15, weight: FontWeight.w500, color: DotColors.faint2),
        filled: true,
        fillColor: DotColors.searchFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DotColors.hairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DotColors.hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: brandRed.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: DotColors.surface,
          borderRadius: BorderRadius.circular(DotRadii.result),
          border: Border.all(color: DotColors.outline),
          boxShadow: DotShadow.result,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit list',
              style: DotText.font(size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _field(_nameCtrl, 'List name', autofocus: true),
            const SizedBox(height: 10),
            _field(_descCtrl, 'What is this list for?'),
            const SizedBox(height: 10),
            _field(_kwCtrl, 'comma-separated, e.g. login, signup, crash'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _DialogButton(
                  label: 'Cancel',
                  filled: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                _DialogButton(
                  label: 'Save',
                  filled: true,
                  enabled: _canSave,
                  onTap: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delete confirmation dialog
// ---------------------------------------------------------------------------

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.ref, required this.bucket});

  final WidgetRef ref;
  final Bucket bucket;

  Future<void> _confirmDelete(BuildContext context) async {
    await ref.read(databaseProvider).deleteBucket(bucket.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: DotColors.surface,
          borderRadius: BorderRadius.circular(DotRadii.result),
          border: Border.all(color: DotColors.outline),
          boxShadow: DotShadow.result,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete "${bucket.name}"?',
              style: DotText.font(size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Its notes move to Unsorted.',
              style: DotText.font(
                size: 14,
                weight: FontWeight.w500,
                color: DotColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _DialogButton(
                  label: 'Cancel',
                  filled: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                _DialogButton(
                  label: 'Delete',
                  filled: true,
                  destructive: true,
                  onTap: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared dialog button
// ---------------------------------------------------------------------------

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color bg = destructive
        ? DotReds.classic
        : filled
            ? DotColors.ink
            : Colors.transparent;
    // Destructive keeps white-on-red; the filled (light ink) pill takes a
    // dark label; outline buttons stay muted.
    final Color fg = destructive
        ? DotColors.white
        : filled
            ? DotColors.canvas
            : DotColors.muted;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: filled
                ? null
                : Border.all(color: DotColors.hairline, width: 1),
          ),
          child: Text(
            label,
            style: DotText.font(
              size: 14,
              weight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
