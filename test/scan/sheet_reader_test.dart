import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/form/form_layout.dart';
import 'package:okutio/core/models/exam.dart';
import 'package:okutio/core/scan/sheet_reader.dart';

import '../support/synthetic_sheet.dart';

Exam _exam({int choice = 20, int open = 2, int booklets = 2}) => (ExamDraft(
  choiceCount: choice,
  openCount: open,
)..bookletCount = booklets).build(id: 'sinav-42', now: DateTime(2026));

final _marks = StudentMarks(
  choices: {
    1: {0},
    2: {1},
    3: {2},
    4: {3},
    5: {0},
    7: {2},
    9: {1, 3}, // çift işaretleme
    12: {3},
    20: {0},
  },
  studentNumber: '1207',
  booklet: 1,
);

void _expectRead(SheetReading r) {
  final marked = {
    for (final c in r.choices)
      if (c.marked.isNotEmpty) c.number: c.marked,
  };
  expect(marked, _marks.choices);
  expect(r.studentNumber, '1207');
  expect(r.studentNumberComplete, isTrue);
  expect(r.bookletIndex, 1);
}

void main() {
  final exam = _exam();
  final layout = FormLayout.compute(exam);
  final sheet = renderSheet(layout.pages.first, _marks);
  final reader = SheetReader(layout);

  SheetReading shoot(Camera cam) => reader.readBytes(photograph(sheet, cam));

  test('düz ve aydınlık fotoğraf', () {
    final r = shoot(const Camera());
    _expectRead(r);
    expect(r.qrText, FormLayout.payloadFor('sinav-42', 0));
    expect(r.warnings, isEmpty);
    expect(r.openAnswers, hasLength(2));
    expect(r.unsureQuestions, isEmpty);
  });

  test('çok karanlık oda (ışık %25)', () {
    final r = shoot(const Camera(brightness: 0.25, noise: 6));
    _expectRead(r);
    expect(r.warnings.join(), contains('karanlık'));
  });

  test('bir yandan düşen koyu gölge', () {
    _expectRead(shoot(const Camera(shadow: 0.7, brightness: 0.8)));
  });

  test('eğik çekim ve hafif döndürme', () {
    _expectRead(shoot(const Camera(tilt: 0.18, rotation: 7)));
  });

  test('bulanık ve gürültülü', () {
    _expectRead(shoot(const Camera(blur: 2, noise: 12)));
  });

  test('ters çekilmiş kâğıt', () {
    _expectRead(shoot(const Camera(upsideDown: true)));
  });

  test('yan (yatay) çekilmiş kâğıt', () {
    _expectRead(shoot(const Camera(rotation: 90, width: 2000, height: 1500)));
  });

  test('hepsi birden: karanlık, gölgeli, eğik, bulanık', () {
    _expectRead(
      shoot(
        const Camera(
          brightness: 0.35,
          shadow: 0.5,
          tilt: 0.12,
          rotation: -5,
          blur: 1,
          noise: 8,
        ),
      ),
    );
  });

  test('silik işaret öğretmene sorulur', () {
    final faint = renderSheet(
      layout.pages.first,
      StudentMarks(faint: {6: 2}, studentNumber: '5'),
    );
    final r = reader.readBytes(photograph(faint, const Camera()));
    expect(r.unsureQuestions, [6]);
    expect(r.choices.firstWhere((c) => c.number == 6).marked, isEmpty);
  });

  test('başka sınavın kâğıdı reddedilir', () {
    final other = FormLayout.compute(
      (ExamDraft(
        choiceCount: 20,
        openCount: 2,
      )..bookletCount = 2).build(id: 'baska-sinav', now: DateTime(2026)),
    );
    final otherSheet = renderSheet(other.pages.first, _marks);
    expect(
      () => reader.readBytes(photograph(otherSheet, const Camera())),
      throwsA(isA<ScanFailure>()),
    );
  });

  test('köşeler kadrajda değilse anlaşılır hata', () {
    expect(
      () => reader.readBytes(photograph(sheet, const Camera(zoom: 1.5))),
      throwsA(
        isA<ScanFailure>().having((e) => e.message, 'mesaj', contains('köşe')),
      ),
    );
  });
}
