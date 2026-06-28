import 'package:record/record.dart';

/// Returns true if microphone permission is granted.
/// On Android this will prompt the user if permission has not yet been granted.
Future<bool> ensureMicPermission() async {
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission();
  } finally {
    await recorder.dispose();
  }
}
