import 'package:flutter/widgets.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/log/app_log.dart';

/// The floating capture button centred at the bottom of the board.
///
/// 72×72 red circle with a pulse ring, a white ring child with white dot,
/// and press-scale feedback (0.92 on down, 1.0 on up/cancel).
class CaptureFab extends StatefulWidget {
  const CaptureFab({super.key, required this.onCapture});

  final VoidCallback onCapture;

  @override
  State<CaptureFab> createState() => _CaptureFabState();
}

class _CaptureFabState extends State<CaptureFab>
    with SingleTickerProviderStateMixin {
  /// Pulse ring animation controller.
  AnimationController? _pulseCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  /// Whether the FAB is being pressed down.
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // Controller + animations initialised but only started after first build
    // so we can check disableAnimations.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final noAnim = MediaQuery.of(context).disableAnimations;
    if (noAnim) {
      _pulseCtrl?.dispose();
      _pulseCtrl = null;
      return;
    }
    if (_pulseCtrl != null) return; // already set up

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.25, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noAnim = MediaQuery.of(context).disableAnimations;
    final fabSize = DotRadii.fab; // 72

    Widget inner = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: DotColors.white, width: 3),
      ),
      child: Center(
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: DotColors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );

    // Pulse ring layer — only when animations are enabled.
    Widget pulseRing;
    if (noAnim || _pulseCtrl == null) {
      // Static faint ring at end-state (invisible) — reduced motion: no ring.
      pulseRing = const SizedBox.shrink();
    } else {
      pulseRing = AnimatedBuilder(
        animation: _pulseCtrl!,
        builder: (_, _) {
          return Opacity(
            opacity: _pulseOpacity.value,
            child: Transform.scale(
              scale: _pulseScale.value,
              child: Container(
                width: fabSize,
                height: fabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: brandRed, width: 2),
                ),
              ),
            ),
          );
        },
      );
    }

    final fabButton = AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeInOut,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          AppLog.instance.log('ui', 'record button tapped');
          widget.onCapture();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: Container(
          width: fabSize,
          height: fabSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(0, -0.24),
              colors: [brandRed, brandRed.withValues(alpha: 0.88)],
            ),
            boxShadow: DotShadow.fab(brandRed),
          ),
          child: Center(child: inner),
        ),
      ),
    );

    return Positioned(
      bottom: 22,
      left: 0,
      right: 0,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            pulseRing,
            fabButton,
          ],
        ),
      ),
    );
  }
}
