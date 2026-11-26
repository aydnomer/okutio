import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/exam.dart';
import '../core/models/student_sheet.dart';
import 'exam_repository.dart';
import 'sheet_repository.dart';

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

final sheetRepositoryProvider = Provider<SheetRepository>(
  (ref) => LocalSheetRepository(SharedPreferencesAsync()),
);

/// Bir sınavın okutulmuş kâğıtları, öğrenci numarasına göre sıralı.
final sheetsProvider =
    AsyncNotifierProvider.family<SheetsNotifier, List<StudentSheet>, String>(
      SheetsNotifier.new,
    );

class SheetsNotifier extends AsyncNotifier<List<StudentSheet>> {
  SheetsNotifier(this.examId);

  final String examId;

  SheetRepository get _repo => ref.read(sheetRepositoryProvider);

  @override
  Future<List<StudentSheet>> build() async =>
      _sorted(await _repo.loadForExam(examId));

  static List<StudentSheet> _sorted(List<StudentSheet> list) =>
      list..sort((a, b) {
        final na = int.tryParse(a.studentNumber);
        final nb = int.tryParse(b.studentNumber);
        if (na != null && nb != null) return na.compareTo(nb);
        if (na != null) return -1;
        if (nb != null) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });

  Future<void> save(StudentSheet sheet, {List<Uint8List>? images}) async {
    await _repo.save(sheet);
    if (images != null) await _repo.saveImages(sheet.id, images);
    final current = [...?state.value];
    final i = current.indexWhere((s) => s.id == sheet.id);
    if (i == -1) {
      current.add(sheet);
    } else {
      current[i] = sheet;
    }
    state = AsyncData(_sorted(current));
  }

  Future<void> delete(StudentSheet sheet) async {
    await _repo.delete(sheet);
    state = AsyncData([
      for (final s in [...?state.value])
        if (s.id != sheet.id) s,
    ]);
  }
}

/// Bir kâğıdın açık uçlu cevap görüntüleri.
final sheetImagesProvider = FutureProvider.family<List<Uint8List>, String>(
  (ref, sheetId) => ref.read(sheetRepositoryProvider).loadImages(sheetId),
);
