/// Optik formun sayfa yerleşimi.
///
/// Tüm ölçüler milimetre, başlangıç noktası sayfanın sol üst köşesidir.
/// Bu dosya tek doğruluk kaynağıdır: PDF çizimi de, ileride kâğıdı okuyacak
/// tarayıcı da aynı koordinatları kullanır. Burada yapılan her değişiklik
/// [FormLayout.version] artırılarak yapılmalıdır; eski kâğıtlar eski
/// sürümle okunur.
library;

import 'dart:math' as math;

import '../models/exam.dart';
import '../models/question.dart';

/// Milimetre cinsinden dikdörtgen.
class MmRect {
  const MmRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  bool overlaps(MmRect o) =>
      left < o.right && o.left < right && top < o.bottom && o.top < bottom;

  bool inside(MmRect o) =>
      left >= o.left - 1e-9 &&
      top >= o.top - 1e-9 &&
      right <= o.right + 1e-9 &&
      bottom <= o.bottom + 1e-9;

  @override
  String toString() =>
      'MmRect(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)} × ${height.toStringAsFixed(1)})';
}

/// İşaretlenecek bir yuvarlak.
class Bubble {
  const Bubble({required this.cx, required this.cy, required this.label});

  /// Merkez, mm.
  final double cx;
  final double cy;

  /// Yuvarlağın içine yazılan harf ya da rakam.
  final String label;

  MmRect get bounds => MmRect(
    cx - FormLayout.bubbleRadius,
    cy - FormLayout.bubbleRadius,
    FormLayout.bubbleRadius * 2,
    FormLayout.bubbleRadius * 2,
  );
}

/// Çoktan seçmeli bir sorunun satırı.
class ChoiceRow {
  const ChoiceRow({
    required this.number,
    required this.labelRect,
    required this.bubbles,
  });

  /// Formdaki (kitapçık) soru numarası.
  final int number;
  final MmRect labelRect;

  /// Şık sırasıyla: A, B, C...
  final List<Bubble> bubbles;
}

/// Öğrenci numarasının bir basamağı: yazma kutusu ve 0-9 yuvarlakları.
class DigitColumn {
  const DigitColumn({required this.writeBox, required this.bubbles});

  final MmRect writeBox;
  final List<Bubble> bubbles;
}

/// Açık uçlu sorunun cevap alanı.
class OpenBox {
  const OpenBox({
    required this.question,
    required this.titleRect,
    required this.promptRect,
    required this.answerRect,
    required this.scoreRect,
  });

  final OpenQuestion question;

  /// "1. soru (25 puan)" yazısı.
  final MmRect titleRect;

  /// Soru metni; metin yoksa yüksekliği 0.
  final MmRect promptRect;

  /// Öğrencinin yazacağı alan. Tarayıcı yalnızca bu alanı keser.
  final MmRect answerRect;

  /// Öğretmenin elle puan yazabileceği küçük kutu (cevap alanının dışında).
  final MmRect scoreRect;
}

class FormPage {
  FormPage({required this.examId, required this.index});

  final String examId;

  /// 0'dan başlar.
  final int index;

  /// Formun toplam sayfa sayısı; yerleşim bitince yazılır.
  int pageCount = 1;

  /// Sayfanın dört köşesindeki hizalama kareleri: sol üst, sağ üst, sol alt, sağ alt.
  final List<MmRect> markers = [];

  late MmRect qr;
  late MmRect header;
  late MmRect nameBox;
  MmRect? instructions;

  final List<DigitColumn> studentNumber = [];
  MmRect? studentNumberFrame;

  final List<Bubble> bookletBubbles = [];
  MmRect? bookletFrame;

  final List<ChoiceRow> choiceRows = [];
  final List<OpenBox> openBoxes = [];
  late MmRect footer;

  /// QR koduna yazılan metin: biçim sürümü, sınav, sayfa.
  String get qrPayload => FormLayout.payloadFor(examId, index);

  /// Bütün yuvarlakları (numara, kitapçık, test soruları) kapsayan bölge.
  /// İşaretlenecek yuvarlak yoksa `null`.
  MmRect? get answerArea {
    final bubbles = [
      for (final d in studentNumber) ...d.bubbles,
      ...bookletBubbles,
      for (final r in choiceRows) ...r.bubbles,
    ];
    if (bubbles.isEmpty) return null;
    const pad = 4.0;
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final x in bubbles) {
      l = math.min(l, x.cx);
      t = math.min(t, x.cy);
      r = math.max(r, x.cx);
      b = math.max(b, x.cy);
    }
    for (final row in choiceRows) {
      l = math.min(l, row.labelRect.left);
    }
    final rad = FormLayout.bubbleRadius + pad;
    l = math.max(0, l - pad);
    t = math.max(0, t - rad);
    r = math.min(FormLayout.pageWidth, r + rad);
    b = math.min(FormLayout.pageHeight, b + rad);
    return MmRect(l, t, r - l, b - t);
  }
}

/// Bir sınavın yazdırılacak formu.
class FormLayout {
  FormLayout._(this.exam, this.pages);

  /// Kâğıt biçiminin sürümü. QR içinde taşınır.
  static const version = 1;

  static const pageWidth = 210.0;
  static const pageHeight = 297.0;

  static const markerSize = 7.0;
  static const markerInset = 8.0;

  /// İçeriğin yerleşebileceği alan (işaretlerin iç tarafı).
  static const content = MmRect(18, 18, 174, 258);

  static const bubbleRadius = 2.3;
  static const optionPitch = 6.6;
  static const rowPitch = 6.4;
  static const studentDigits = 5;

  static const qrSize = 24.0;

  /// Açık uçlu cevap alanında bir yazı satırının yüksekliği.
  static const answerLineHeight = 7.0;

  final Exam exam;
  final List<FormPage> pages;

  static String payloadFor(String examId, int page) =>
      'OKUTIO|$version|$examId|${page + 1}';

  /// QR metnini çözer. Okutio formu değilse `null`.
  static ({int version, String examId, int page})? parsePayload(String s) {
    final parts = s.split('|');
    if (parts.length != 4 || parts[0] != 'OKUTIO') return null;
    final v = int.tryParse(parts[1]);
    final p = int.tryParse(parts[3]);
    if (v == null || p == null || p < 1 || parts[2].isEmpty) return null;
    return (version: v, examId: parts[2], page: p - 1);
  }

  static FormLayout compute(Exam exam) {
    final pages = (_Builder(exam)..run()).pages;
    for (final p in pages) {
      p.pageCount = pages.length;
    }
    return FormLayout._(exam, pages);
  }
}

class _Builder {
  _Builder(this.exam);

  final Exam exam;
  final pages = <FormPage>[];

  static const _c = FormLayout.content;
  static const _gap = 4.0;
  static const _labelW = 8.0;
  static const _colGap = 3.0;

  /// Bir sütundaki en çok soru satırı (okunaklılık için).
  static const _maxRowsPerColumn = 25;

  late FormPage _page;
  late double _y;

  /// Öğrenci numarası bloğunun sağında kalan boş alan; önce test soruları buraya yerleşir.
  MmRect? _side;

  double get _colW => _labelW + exam.optionCount * FormLayout.optionPitch;

  void run() {
    _newPage();
    _choiceGrid();
    for (final q in exam.openQuestions) {
      _openBox(q);
    }
    for (final p in pages) {
      _stretchOpenBoxes(p);
    }
  }

  /// Sayfanın altında boş yer kaldıysa açık uçlu cevap alanlarına satır
  /// olarak paylaştırır: öğrenciye daha çok yazı yeri, aynı kâğıt.
  void _stretchOpenBoxes(FormPage p) {
    final boxes = p.openBoxes;
    if (boxes.isEmpty) return;
    const lineH = FormLayout.answerLineHeight;
    final free = _c.bottom - boxes.last.answerRect.bottom;
    final extra = (free / boxes.length / lineH).floor();
    if (extra < 1) return;
    var shift = 0.0;
    for (var i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      MmRect moved(MmRect r) =>
          MmRect(r.left, r.top + shift, r.width, r.height);
      final answer = moved(b.answerRect);
      boxes[i] = OpenBox(
        question: b.question,
        titleRect: moved(b.titleRect),
        promptRect: moved(b.promptRect),
        scoreRect: moved(b.scoreRect),
        answerRect: MmRect(
          answer.left,
          answer.top,
          answer.width,
          answer.height + extra * lineH,
        ),
      );
      shift += extra * lineH;
    }
  }

  void _newPage() {
    _page = FormPage(examId: exam.id, index: pages.length);
    pages.add(_page);
    const s = FormLayout.markerSize;
    const i = FormLayout.markerInset;
    _page.markers.addAll(const [
      MmRect(i, i, s, s),
      MmRect(FormLayout.pageWidth - i - s, i, s, s),
      MmRect(i, FormLayout.pageHeight - i - s, s, s),
      MmRect(FormLayout.pageWidth - i - s, FormLayout.pageHeight - i - s, s, s),
    ]);
    _page.qr = MmRect(
      _c.right - FormLayout.qrSize,
      _c.top,
      FormLayout.qrSize,
      FormLayout.qrSize,
    );
    _page.header = MmRect(_c.left, _c.top, _page.qr.left - _c.left - _gap, 12);
    _page.nameBox = MmRect(_c.left, _c.top + 13, _page.header.width, 11);
    _page.footer = MmRect(_c.left, FormLayout.pageHeight - 15, _c.width, 5);
    _y = _c.top + FormLayout.qrSize + 2;

    if (pages.length == 1) {
      _page.instructions = MmRect(_c.left, _y, _c.width, 6);
      _y += 8;
    }
    // Her sayfada öğrenci numarası olsun: sayfalar birbirinden ayrılsa da
    // aynı öğrenciye bağlanabilsin.
    _studentBlock();
  }

  void _studentBlock() {
    final y0 = _y;
    const colPitch = 6.6;
    const writeBox = 5.6;
    const labelH = 5.0;
    const digitPitch = 5.0;
    final digitsTop = y0 + labelH + writeBox + 2;
    for (var d = 0; d < FormLayout.studentDigits; d++) {
      final cx = _c.left + 4 + colPitch * d + colPitch / 2;
      _page.studentNumber.add(
        DigitColumn(
          writeBox: MmRect(cx - writeBox / 2, y0 + labelH, writeBox, writeBox),
          bubbles: [
            for (var v = 0; v < 10; v++)
              Bubble(
                cx: cx,
                cy: digitsTop + FormLayout.bubbleRadius + v * digitPitch,
                label: '$v',
              ),
          ],
        ),
      );
    }
    final frame = MmRect(
      _c.left,
      y0,
      8 + colPitch * FormLayout.studentDigits,
      _page.studentNumber.first.bubbles.last.bounds.bottom + 2 - y0,
    );
    _page.studentNumberFrame = frame;

    var sideTop = y0;
    final sideLeft = frame.right + _gap;
    if (exam.usesBooklets) {
      final n = exam.booklets.length;
      _page.bookletFrame = MmRect(
        sideLeft,
        y0,
        math.max(24, 8 + n * FormLayout.optionPitch),
        14,
      );
      for (var b = 0; b < n; b++) {
        _page.bookletBubbles.add(
          Bubble(
            cx:
                sideLeft +
                4 +
                FormLayout.bubbleRadius +
                b * FormLayout.optionPitch,
            cy: y0 + 9.5,
            label: exam.booklets[b].code,
          ),
        );
      }
      sideTop = _page.bookletFrame!.bottom + _gap;
    }
    _side = MmRect(
      sideLeft,
      sideTop,
      _c.right - sideLeft,
      frame.bottom - sideTop,
    );
    _y = frame.bottom + _gap;
  }

  /// [region] içine en fazla [maxCount] soru yerleştirir, kaç tane koyduğunu döner.
  ///
  /// Sütunlar dengeli doldurulur: 10 soru 3 sütuna 4-3-3 değil 4-4-2 düşer,
  /// böylece öğrenci soruları yukarıdan aşağı sırayla bulur.
  int _placeIn(MmRect region, int first, int maxCount) {
    final cols = math.min(
      ((region.width + _colGap) / (_colW + _colGap)).floor(),
      maxCount,
    );
    final rowsCap = math.min(
      (region.height / FormLayout.rowPitch).floor(),
      _maxRowsPerColumn,
    );
    if (cols < 1 || rowsCap < 1) return 0;
    final rows = math.min(rowsCap, (maxCount / cols).ceil());
    final usedCols = (math.min(maxCount, rows * cols) / rows).ceil();
    final spare = region.width - usedCols * _colW;
    final gap = usedCols > 1 ? math.min(spare / (usedCols - 1), 10.0) : 0.0;
    var placed = 0;
    for (var col = 0; col < usedCols; col++) {
      final x0 = region.left + col * (_colW + gap);
      for (var r = 0; r < rows && placed < maxCount; r++) {
        final cy = region.top + FormLayout.rowPitch * (r + 0.5);
        _page.choiceRows.add(
          ChoiceRow(
            number: first + placed,
            labelRect: MmRect(x0, cy - 2.5, _labelW - 1, 5),
            bubbles: [
              for (var o = 0; o < exam.optionCount; o++)
                Bubble(
                  cx:
                      x0 +
                      _labelW +
                      FormLayout.optionPitch * o +
                      FormLayout.bubbleRadius,
                  cy: cy,
                  label: optionLetters[o],
                ),
            ],
          ),
        );
        placed++;
      }
    }
    return placed;
  }

  void _choiceGrid() {
    final total = exam.choiceCount;
    var next = 1;
    while (next <= total) {
      final side = _side;
      if (side != null) {
        next += _placeIn(side, next, total - next + 1);
        _side = null;
        continue;
      }
      final below = MmRect(_c.left, _y, _c.width, _c.bottom - _y);
      final placed = _placeIn(below, next, total - next + 1);
      if (placed > 0) {
        final rows = _page.choiceRows
            .where((r) => r.number >= next)
            .map((r) => r.labelRect.top)
            .toSet()
            .length;
        _y += rows * FormLayout.rowPitch + _gap;
        next += placed;
      }
      if (next <= total) _newPage();
    }
    _side = null;
  }

  /// Soru metni için kabaca satır sayısı (9 punto, yaklaşık 95 karakter/satır).
  static int _promptLines(String text) {
    if (text.trim().isEmpty) return 0;
    var lines = 0;
    for (final para in text.trim().split('\n')) {
      lines += math.max(1, (para.length / 95).ceil());
    }
    return math.min(lines, 8);
  }

  void _openBox(OpenQuestion q) {
    const titleH = 6.0;
    const lineH = 4.4;
    final promptH = _promptLines(q.prompt) * lineH;
    final answerH = q.answerLines * FormLayout.answerLineHeight;
    final needed = titleH + promptH + 1 + answerH;
    if (_y + needed > _c.bottom) {
      _newPage();
      _side = null;
    }
    // Çok uzun bir alan bile tek sayfaya sığmalı.
    final h = math.min(answerH, _c.bottom - _y - titleH - promptH - 1);

    const scoreW = 24.0;
    final titleRect = MmRect(_c.left, _y, _c.width - scoreW - 2, titleH);
    final scoreRect = MmRect(_c.right - scoreW, _y, scoreW, titleH);
    final promptRect = MmRect(_c.left, _y + titleH, _c.width, promptH);
    final answerRect = MmRect(_c.left, promptRect.bottom + 1, _c.width, h);
    _page.openBoxes.add(
      OpenBox(
        question: q,
        titleRect: titleRect,
        promptRect: promptRect,
        answerRect: answerRect,
        scoreRect: scoreRect,
      ),
    );
    _y = answerRect.bottom + 3;
  }
}
