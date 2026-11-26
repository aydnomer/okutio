import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/student_sheet.dart';

/// Öğrenci kâğıtlarını ve açık uçlu cevap görüntülerini saklar.
///
/// Şimdilik cihazda. Görüntüler ayrı anahtarlarda tutulur ki kâğıt listesi
/// hızlı açılsın.
abstract interface class SheetRepository {
  Future<List<StudentSheet>> loadForExam(String examId);
  Future<void> save(StudentSheet sheet);
  Future<void> delete(StudentSheet sheet);
  Future<void> saveImages(String sheetId, List<Uint8List> images);
  Future<List<Uint8List>> loadImages(String sheetId);
}

class LocalSheetRepository implements SheetRepository {
  LocalSheetRepository(this._prefs);

  final SharedPreferencesAsync _prefs;

  static String _key(String examId) => 'okutio.sheets.v1.$examId';
  static String _imgKey(String sheetId) => 'okutio.openimg.v1.$sheetId';

  @override
  Future<List<StudentSheet>> loadForExam(String examId) async {
    final raw = await _prefs.getString(_key(examId));
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List<Object?>)
        StudentSheet.fromJson((e! as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> save(StudentSheet sheet) async {
    final all = await loadForExam(sheet.examId);
    final i = all.indexWhere((s) => s.id == sheet.id);
    if (i == -1) {
      all.add(sheet);
    } else {
      all[i] = sheet;
    }
    await _prefs.setString(
      _key(sheet.examId),
      jsonEncode([for (final s in all) s.toJson()]),
    );
  }

  @override
  Future<void> delete(StudentSheet sheet) async {
    final all = await loadForExam(sheet.examId)
      ..removeWhere((s) => s.id == sheet.id);
    await _prefs.setString(
      _key(sheet.examId),
      jsonEncode([for (final s in all) s.toJson()]),
    );
    await _prefs.remove(_imgKey(sheet.id));
  }

  @override
  Future<void> saveImages(String sheetId, List<Uint8List> images) async {
    try {
      await _prefs.setStringList(_imgKey(sheetId), [
        for (final i in images) base64Encode(i),
      ]);
    } on Object {
      // Tarayıcı depolama sınırı dolduysa görüntüler saklanmaz; puanlar
      // yine de kaydedilir.
    }
  }

  @override
  Future<List<Uint8List>> loadImages(String sheetId) async {
    final list = await _prefs.getStringList(_imgKey(sheetId));
    return [for (final s in list ?? const <String>[]) base64Decode(s)];
  }
}

class InMemorySheetRepository implements SheetRepository {
  final _sheets = <String, StudentSheet>{};
  final _images = <String, List<Uint8List>>{};

  @override
  Future<List<StudentSheet>> loadForExam(String examId) async => [
    for (final s in _sheets.values)
      if (s.examId == examId) s,
  ];

  @override
  Future<void> save(StudentSheet sheet) async => _sheets[sheet.id] = sheet;

  @override
  Future<void> delete(StudentSheet sheet) async {
    _sheets.remove(sheet.id);
    _images.remove(sheet.id);
  }

  @override
  Future<void> saveImages(String sheetId, List<Uint8List> images) async =>
      _images[sheetId] = images;

  @override
  Future<List<Uint8List>> loadImages(String sheetId) async =>
      _images[sheetId] ?? const [];
}
