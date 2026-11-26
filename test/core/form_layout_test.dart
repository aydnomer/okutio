import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/form/form_layout.dart';
import 'package:okutio/core/models/exam.dart';

Exam _exam({
  int choice = 20,
  int open = 0,
  int options = 4,
  int booklets = 1,
  int lines = 4,
  String prompt = '',
}) {
  final draft = ExamDraft(
    choiceCount: choice,
    openCount: open,
    optionCount: options,
    openPointsEach: open == 0 ? 10 : (40 / open).floorToDouble(),
  )..bookletCount = booklets;
  final e = draft.build(id: 'sinav-1', now: DateTime(2026));
  return e.copyWith(
    openQuestions: [
      for (final q in e.openQuestions)
        q.copyWith(answerLines: lines, prompt: prompt),
    ],
  );
}

/// Bir sayfadaki tüm "dokunulmaması gereken" alanlar.
List<(String, MmRect)> _regions(FormPage p) => [
  for (final (i, m) in p.markers.indexed) ('işaret $i', m),
  ('qr', p.qr),
  ('başlık', p.header),
  ('ad', p.nameBox),
  if (p.studentNumberFrame != null) ('öğrenci no', p.studentNumberFrame!),
  if (p.bookletFrame != null) ('kitapçık', p.bookletFrame!),
  if (p.instructions != null) ('açıklama', p.instructions!),
  for (final r in p.choiceRows)
    (
      'soru ${r.number}',
      MmRect(
        r.labelRect.left,
        r.bubbles.first.bounds.top,
        r.bubbles.last.bounds.right - r.labelRect.left,
        r.bubbles.first.bounds.height,
      ),
    ),
  for (final b in p.openBoxes) ...[
    ('açık ${b.question.number} başlık', b.titleRect),
    ('açık ${b.question.number} puan', b.scoreRect),
    ('açık ${b.question.number} alan', b.answerRect),
  ],
  ('alt bilgi', p.footer),
];

void _expectClean(FormLayout layout) {
  for (final p in layout.pages) {
    final regions = _regions(p);
    for (var i = 0; i < regions.length; i++) {
      final (name, r) = regions[i];
      expect(r.width, greaterThan(0), reason: '$name genişliği');
      const page = MmRect(0, 0, FormLayout.pageWidth, FormLayout.pageHeight);
      expect(r.inside(page), isTrue, reason: '$name sayfa dışında: $r');
      if (!name.startsWith('işaret') && name != 'alt bilgi') {
        expect(
          r.inside(FormLayout.content),
          isTrue,
          reason: 'sayfa ${p.index + 1}: $name içerik alanı dışında: $r',
        );
      }
      for (var j = i + 1; j < regions.length; j++) {
        final (other, o) = regions[j];
        expect(
          r.overlaps(o),
          isFalse,
          reason: 'sayfa ${p.index + 1}: $name ile $other çakışıyor: $r / $o',
        );
      }
    }
  }
}

void main() {
  test('okul yazılısı tek sayfaya sığar', () {
    final layout = FormLayout.compute(_exam(choice: 10, open: 4));
    expect(layout.pages, hasLength(1));
    final p = layout.pages.single;
    expect(p.choiceRows, hasLength(10));
    expect(p.openBoxes, hasLength(4));
    expect(p.markers, hasLength(4));
    expect(p.studentNumber, hasLength(FormLayout.studentDigits));
    expect(p.studentNumber.first.bubbles, hasLength(10));
    _expectClean(layout);
  });

  test('her soru bir kez, sırayla yerleşir', () {
    final layout = FormLayout.compute(_exam(choice: 120, options: 5));
    final numbers = [
      for (final p in layout.pages)
        for (final r in p.choiceRows) r.number,
    ];
    expect(numbers, List.generate(120, (i) => i + 1));
    expect(layout.pages.first.choiceRows.first.bubbles, hasLength(5));
    _expectClean(layout);
  });

  test('120 soruluk TYT denemesi tek sayfaya sığar', () {
    final layout = FormLayout.compute(_exam(choice: 120, options: 5));
    expect(layout.pages, hasLength(1));
  });

  test('sığmayan sorular sonraki sayfaya geçer, sayfa sayısı her sayfada', () {
    final layout = FormLayout.compute(_exam(choice: 160, options: 5));
    expect(layout.pages, hasLength(2));
    expect(layout.pages.every((p) => p.pageCount == 2), isTrue);
    expect(layout.pages[1].instructions, isNull);
    expect(layout.pages[1].studentNumber, isNotEmpty);
    _expectClean(layout);
  });

  test('uzun açık uçlu sorular yeni sayfaya geçer', () {
    final layout = FormLayout.compute(
      _exam(choice: 20, open: 6, lines: 10, prompt: 'Açıklayınız. ' * 20),
    );
    expect(layout.pages.length, greaterThan(1));
    final open = [
      for (final p in layout.pages)
        for (final b in p.openBoxes) b.question.number,
    ];
    expect(open, [1, 2, 3, 4, 5, 6]);
    for (final p in layout.pages) {
      for (final b in p.openBoxes) {
        expect(
          b.answerRect.height,
          10 * FormLayout.answerLineHeight,
          reason: 'alan kısaltılmamalı',
        );
      }
    }
    _expectClean(layout);
  });

  test('kitapçıklı sınavda kitapçık yuvarlakları var', () {
    final layout = FormLayout.compute(_exam(booklets: 4));
    final p = layout.pages.first;
    expect(p.bookletBubbles.map((b) => b.label), ['A', 'B', 'C', 'D']);
    _expectClean(layout);
  });

  test('yalnız açık uçlu sınav', () {
    final layout = FormLayout.compute(_exam(choice: 0, open: 3));
    expect(layout.pages.first.choiceRows, isEmpty);
    expect(layout.pages.first.openBoxes, hasLength(3));
    _expectClean(layout);
  });

  test('QR metni yazılıp geri okunur', () {
    final layout = FormLayout.compute(_exam(choice: 160, options: 5));
    final parsed = FormLayout.parsePayload(layout.pages[1].qrPayload);
    expect(parsed, isNotNull);
    expect(parsed!.examId, 'sinav-1');
    expect(parsed.page, 1);
    expect(parsed.version, FormLayout.version);
    expect(FormLayout.parsePayload('başka bir QR'), isNull);
    expect(FormLayout.parsePayload('OKUTIO|1|x|0'), isNull);
  });

  test('yuvarlaklar yazıcı ve tarayıcı için yeterince ayrık', () {
    final layout = FormLayout.compute(_exam(choice: 100, options: 5));
    for (final p in layout.pages) {
      for (final r in p.choiceRows) {
        for (var i = 1; i < r.bubbles.length; i++) {
          final gap = r.bubbles[i].bounds.left - r.bubbles[i - 1].bounds.right;
          expect(gap, greaterThanOrEqualTo(1.5));
        }
      }
    }
  });
}
