import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/exam.dart';

/// Sınavları saklar.
///
/// İlk sürümde veriler cihazda tutulur. Sunucuya geçildiğinde (Supabase) yalnızca
/// bu sınıfın yeni bir uygulaması yazılır; ekranlar değişmez.
abstract interface class ExamRepository {
  Future<List<Exam>> loadAll();
  Future<void> save(Exam exam);
  Future<void> delete(String id);
}

class LocalExamRepository implements ExamRepository {
  LocalExamRepository(this._prefs);

  static const _key = 'okutio.exams.v1';
  final SharedPreferencesAsync _prefs;

  @override
  Future<List<Exam>> loadAll() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List<Object?>)
        .map((e) => Exam.fromJson((e! as Map).cast<String, Object?>()))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> save(Exam exam) async {
    final all = await loadAll();
    final index = all.indexWhere((e) => e.id == exam.id);
    if (index == -1) {
      all.insert(0, exam);
    } else {
      all[index] = exam;
    }
    await _write(all);
  }

  @override
  Future<void> delete(String id) async {
    final all = await loadAll()
      ..removeWhere((e) => e.id == id);
    await _write(all);
  }

  Future<void> _write(List<Exam> exams) =>
      _prefs.setString(_key, jsonEncode([for (final e in exams) e.toJson()]));
}

/// Testlerde ve önizlemede kullanılan bellek içi depo.
class InMemoryExamRepository implements ExamRepository {
  final _exams = <String, Exam>{};

  @override
  Future<List<Exam>> loadAll() async =>
      _exams.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(Exam exam) async => _exams[exam.id] = exam;

  @override
  Future<void> delete(String id) async => _exams.remove(id);
}
