/// Sınıfın sonuç özeti ve PDF listesi.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../form/form_pdf.dart';
import '../models/exam.dart';
import '../models/student_sheet.dart';
import '../scoring/scoring_engine.dart';
import '../util/format.dart';

class QuestionStat {
  const QuestionStat(this.number, this.correct, this.wrong, this.blank);

  /// Ana kitapçıktaki soru numarası.
  final int number;
  final int correct;
  final int wrong;
  final int blank;

  int get answered => correct + wrong + blank;
  double get correctRate => answered == 0 ? 0 : correct / answered;
}

class ClassReport {
  ClassReport(this.exam, List<StudentSheet> sheets)
    : sheets = sheets,
      scores = [for (final s in sheets) s.score(exam)];

  final Exam exam;
  final List<StudentSheet> sheets;
  final List<ScoreResult> scores;

  int get count => sheets.length;

  double get average =>
      count == 0 ? 0 : scores.fold<double>(0, (a, s) => a + s.total) / count;

  double get highest => scores.fold<double>(0, (a, s) => math.max(a, s.total));

  double get lowest =>
      count == 0 ? 0 : scores.map((s) => s.total).reduce(math.min);

  /// 50 ve üstü alanların oranı (okul yazılısında geçme notu).
  double get passRate =>
      count == 0 ? 0 : scores.where((s) => s.total >= 50).length / count;

  /// İptal edilen soruların numaraları.
  List<int> get cancelledNumbers => [
    for (final q in exam.choiceQuestions)
      if (q.cancelled) q.number,
  ];

  int get pendingReview =>
      sheets.where((s) => !s.reviewed && s.issues(exam).isNotEmpty).length;

  /// Ana kitapçık sırasıyla her sorunun doğru/yanlış/boş sayıları.
  List<QuestionStat> questionStats() {
    final stats = <int, List<int>>{
      for (final q in exam.choiceQuestions) q.number: [0, 0, 0],
    };
    for (final s in scores) {
      for (final q in s.questions) {
        final row = stats[q.masterNumber];
        if (row == null) continue;
        switch (q.outcome) {
          case QuestionOutcome.correct:
            row[0]++;
          case QuestionOutcome.wrong:
            row[1]++;
          case QuestionOutcome.blank:
            row[2]++;
          case QuestionOutcome.cancelled:
            break;
        }
      }
    }
    return [
      for (final q in exam.choiceQuestions)
        if (!q.cancelled)
          QuestionStat(
            q.number,
            stats[q.number]![0],
            stats[q.number]![1],
            stats[q.number]![2],
          ),
    ];
  }

  /// En çok yanlış yapılan sorular (konu tekrarı için).
  List<QuestionStat> hardest({int limit = 5}) {
    final list = questionStats().where((s) => s.answered > 0).toList()
      ..sort((a, b) => a.correctRate.compareTo(b.correctRate));
    return list.take(limit).where((s) => s.correctRate < 0.6).toList();
  }

  /// Yazdırılabilir sınıf listesi.
  Future<Uint8List> pdf(FormFonts fonts, {DateTime? date}) {
    final doc = pw.Document(
      title: '${exam.title} sonuçları',
      creator: 'Okutio',
    );
    final base = pw.TextStyle(font: fonts.regular, fontSize: 9.5);
    final bold = pw.TextStyle(font: fonts.bold, fontSize: 9.5);
    final hasChoice = exam.choiceCount > 0;
    final hasNet = exam.rules.wrongPenaltyDivisor != null;
    final headers = [
      'No',
      'Adı',
      if (exam.usesBooklets) 'Kit.',
      if (hasChoice) ...['D', 'Y', 'B'],
      if (hasNet) 'Net',
      if (exam.openCount > 0) 'Açık uçlu',
      'Puan',
    ];
    final rows = [
      for (var i = 0; i < count; i++)
        [
          sheets[i].studentNumber,
          sheets[i].studentName,
          if (exam.usesBooklets) sheets[i].bookletCode ?? '',
          if (hasChoice) ...[
            '${scores[i].correct}',
            '${scores[i].wrong}',
            '${scores[i].blank}',
          ],
          if (hasNet) fmtNum(scores[i].net),
          if (exam.openCount > 0)
            scores[i].openPending > 0
                ? '${fmtNum(scores[i].openScore)} (eksik)'
                : fmtNum(scores[i].openScore),
          fmtNum(scores[i].total),
        ],
    ];
    final stats = questionStats();
    final details = [
      if (exam.subject.isNotEmpty) exam.subject,
      if (exam.classGroup.isNotEmpty) exam.classGroup,
      DateFormat('d MMMM y', 'tr').format(date ?? DateTime.now()),
    ].join(' · ');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              exam.title,
              style: pw.TextStyle(font: fonts.bold, fontSize: 15),
            ),
            pw.Text(details, style: base),
            pw.SizedBox(height: 6),
            pw.Text(
              '$count öğrenci · ortalama ${fmtNum(average, maxDecimals: 1)} · '
              'en yüksek ${fmtNum(highest)} · en düşük ${fmtNum(lowest)}',
              style: bold,
            ),
            if (cancelledNumbers.isNotEmpty)
              pw.Text(
                'İptal edilen sorular: ${cancelledNumbers.join(', ')} '
                '(${exam.rules.cancelPolicy.label.toLowerCase()})',
                style: base,
              ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Okutio · ${ctx.pageNumber}/${ctx.pagesCount}',
            style: base.copyWith(color: PdfColors.grey600, fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: bold,
            cellStyle: base,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
            cellAlignments: {
              for (var c = 0; c < headers.length; c++)
                c: c == 1 ? pw.Alignment.centerLeft : pw.Alignment.center,
            },
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
          if (stats.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Soru bazında sonuçlar',
              style: pw.TextStyle(font: fonts.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Soru', 'Doğru', 'Yanlış', 'Boş', 'Doğru oranı'],
              data: [
                for (final q in stats)
                  [
                    '${q.number}',
                    '${q.correct}',
                    '${q.wrong}',
                    '${q.blank}',
                    '%${(q.correctRate * 100).round()}',
                  ],
              ],
              headerStyle: bold,
              cellStyle: base,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              cellAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
