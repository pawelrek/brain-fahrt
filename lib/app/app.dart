import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/providers.dart';
import '../features/bucket_detail/bucket_detail_screen.dart';
import '../features/capture/capture_overlay.dart';
import '../features/dashboard/dashboard_screen.dart';
import 'theme.dart';

/// Root of the Dot app: the dashboard board is home; tapping a card pushes the
/// bucket detail; the FAB opens the capture overlay (a transparent modal route).
class DotApp extends ConsumerWidget {
  const DotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(fontSizeProvider).scale;
    return MaterialApp(
      title: 'brain-fahrt',
      debugShowCheckedModeBanner: false,
      theme: buildDotTheme(),
      // Give every route a Material ancestor (transparent, so the capture
      // overlay's scrim still shows through) — without it, Text renders with
      // the debug "missing Material" yellow underline.
      // Also apply the user's font-size preference app-wide via MediaQuery.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: child!,
        ),
      ),
      home: const _DashboardHost(),
    );
  }
}

class _DashboardHost extends StatelessWidget {
  const _DashboardHost();

  @override
  Widget build(BuildContext context) {
    return DashboardScreen(
      onOpenBucket: (bucketId) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (routeContext) => BucketDetailScreen(
            bucketId: bucketId,
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
      onCapture: () => showCaptureOverlay(context),
    );
  }
}
