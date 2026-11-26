import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/exam.dart';
import 'exam_repository.dart';

final examRepositoryProvider = Provider<ExamRepository>(
  (ref) => LocalExamRepository(SharedPreferencesAsync()),
);

/// Öğretmenin tüm sınavları, en yenisi başta.
final examListProvider = AsyncNotifierProvider<ExamListNotifier, List<Exam>>(
  ExamListNotifier.new,
);

class ExamListNotifier extends AsyncNotifier<List<Exam>> {
  ExamRepository get _repo => ref.read(examRepositoryProvider);

  @override
  Future<List<Exam>> build() => _repo.loadAll();

  Future<void> save(Exam exam) async {
    await _repo.save(exam);
    state = AsyncData(await _repo.loadAll());
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    state = AsyncData(await _repo.loadAll());
  }
}

/// Tek bir sınav; bulunamazsa `null`.
final examByIdProvider = Provider.family<AsyncValue<Exam?>, String>((ref, id) {
  return ref.watch(examListProvider).whenData((list) {
    for (final e in list) {
      if (e.id == id) return e;
    }
    return null;
  });
});
