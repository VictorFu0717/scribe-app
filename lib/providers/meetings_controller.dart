import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meeting.dart';
import '../models/transcript_segment.dart';
import 'service_providers.dart';

/// 會議清單。對應 `GET /meetings`。
final meetingsListProvider =
    AsyncNotifierProvider<MeetingsListController, List<Meeting>>(
        MeetingsListController.new);

class MeetingsListController extends AsyncNotifier<List<Meeting>> {
  @override
  Future<List<Meeting>> build() {
    return ref.watch(backendProvider).listMeetings();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(backendProvider).listMeetings());
  }

  Future<Meeting> create(String title) async {
    final meeting = await ref.read(backendProvider).createMeeting(title: title);
    ref.invalidateSelf();
    return meeting;
  }

  Future<void> delete(String id) async {
    await ref.read(backendProvider).deleteMeeting(id);
    ref.invalidateSelf();
  }
}

/// 單場會議詳情。
final meetingProvider =
    FutureProvider.family<Meeting, String>((ref, id) async {
  return ref.watch(backendProvider).getMeeting(id);
});

/// 逐字稿(已完成的會議)。
final transcriptProvider =
    FutureProvider.family<List<TranscriptSegment>, String>((ref, id) async {
  return ref.watch(backendProvider).getTranscript(id);
});
