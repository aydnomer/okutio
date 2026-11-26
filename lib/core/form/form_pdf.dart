/// Optik formu PDF olarak çizer. Yerleşim [FormLayout]'tan gelir; burada
/// yalnızca görünüş vardır.
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/exam.dart';
import '../util/format.dart';
import 'form_layout.dart';

/// Türkçe karakterleri (ş, ğ, ı, İ) basabilmek için gömülü yazı tipleri.
class FormFonts {
  const FormFonts({required this.regular, required this.bold});

  factory FormFonts.fromBytes({
    required ByteData regular,
    required ByteData bold,
  }) => FormFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));

  final pw.Font regular;
  final pw.Font bold;
}

class FormPdf {
  FormPdf(this.layout, this.fonts, {DateTime? date})
    : date = date ?? DateTime.now();

  final FormLayout layout;
  final FormFonts fonts;
  final DateTime date;

  Exam get exam => layout.exam;

  static double mm(double v) => v * PdfPageFormat.mm;

  static const _ink = PdfColors.black;

  /// Yuvarlak çizgileri ve içindeki harfler açık gri: öğrencinin kurşun
  /// kalem izi bunlardan kolayca ayrılsın.
  static const _bubbleInk = PdfColor(0.45, 0.45, 0.45);
  static const _labelInk = PdfColor(0.6, 0.6, 0.6);
  static const _guideInk = PdfColor(0.8, 0.8, 0.8);

  /// [copies] kadar form (her biri tüm sayfalarıyla) içeren PDF.
  Future<Uint8List> build({int copies = 1}) {
    final doc = pw.Document(
      title: exam.title,
      author: 'Okutio',
      creator: 'Okutio',
      subject: 'Optik form',
    );
    for (var c = 0; c < copies; c++) {
      for (final page in layout.pages) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
            build: (_) => pw.Stack(children: _page(page)),
          ),
        );
      }
    }
    return doc.save();
  }

  pw.Widget _at(MmRect r, pw.Widget child) => pw.Positioned(
    left: mm(r.left),
    top: mm(r.top),
    child: pw.SizedBox(width: mm(r.width), height: mm(r.height), child: child),
  );

  pw.TextStyle _text(double size, {bool bold = false, PdfColor? color}) =>
      pw.TextStyle(
        font: bold ? fonts.bold : fonts.regular,
        fontSize: size,
        color: color ?? _ink,
      );

  List<pw.Widget> _page(FormPage p) {
    return [
      for (final m in p.markers) _at(m, pw.Container(color: _ink)),
      _at(
        p.qr,
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(
            errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
          ),
          data: p.qrPayload,
          drawText: false,
        ),
      ),
      _at(p.header, _header()),
      _at(p.nameBox, _nameBox()),
      if (p.instructions != null) _at(p.instructions!, _instructions()),
      if (p.studentNumberFrame != null)
        _at(p.studentNumberFrame!, _frame('Öğrenci No')),
      for (final d in p.studentNumber) ...[
        _at(
          d.writeBox,
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _bubbleInk, width: 0.6),
            ),
          ),
        ),
        for (final b in d.bubbles) _bubble(b),
      ],
      if (p.bookletFrame != null) _at(p.bookletFrame!, _frame('Kitapçık')),
      for (final b in p.bookletBubbles) _bubble(b),
      for (final r in p.choiceRows) ...[
        _at(
          r.labelRect,
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('${r.number}', style: _text(8, bold: true)),
          ),
        ),
        for (final b in r.bubbles) _bubble(b),
      ],
      for (final o in p.openBoxes) ..._openBox(o),
      _at(
        p.footer,
        pw.Center(
          child: pw.Text(
            'Okutio · ${exam.title} · Sayfa ${p.index + 1}/${p.pageCount} · '
            'Kâğıdı katlamayın, köşelerdeki karelere ve QR koda yazı yazmayın.',
            style: _text(6.5, color: _labelInk),
          ),
        ),
      ),
    ];
  }

  pw.Widget _header() {
    final details = [
      if (exam.subject.isNotEmpty) exam.subject,
      if (exam.classGroup.isNotEmpty) exam.classGroup,
      DateFormat('d MMMM y', 'tr').format(date),
    ].join(' · ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          exam.title,
          style: _text(12.5, bold: true),
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
        ),
        pw.SizedBox(height: 1.5),
        pw.Text(details, style: _text(8.5)),
      ],
    );
  }

  pw.Widget _labeled(String label, {int flex = 1}) => pw.Expanded(
    flex: flex,
    child: pw.Container(
      padding: const pw.EdgeInsets.only(left: 3, top: 2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _ink, width: 0.7),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      alignment: pw.Alignment.topLeft,
      child: pw.Text(label, style: _text(6.5, color: _bubbleInk)),
    ),
  );

  pw.Widget _nameBox() => pw.Row(
    children: [
      _labeled('Adı Soyadı', flex: 3),
      pw.SizedBox(width: mm(2)),
      _labeled('Sınıf / Şube'),
    ],
  );

  pw.Widget _frame(String title) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _ink, width: 0.7),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    alignment: pw.Alignment.topCenter,
    padding: const pw.EdgeInsets.only(top: 2.5),
    child: pw.Text(title, style: _text(7, bold: true)),
  );

  pw.Widget _sample({required bool good, required int kind}) {
    final r = mm(FormLayout.bubbleRadius);
    return pw.SizedBox(
      width: r * 2,
      height: r * 2,
      child: pw.CustomPaint(
        size: PdfPoint(r * 2, r * 2),
        painter: (canvas, size) {
          canvas
            ..setStrokeColor(_ink)
            ..setLineWidth(0.6)
            ..drawEllipse(r, r, r - 0.3, r - 0.3);
          if (good) {
            canvas
              ..setFillColor(_ink)
              ..fillPath();
            return;
          }
          canvas.strokePath();
          if (kind == 0) {
            // Çentik
            canvas
              ..moveTo(r * 0.5, r)
              ..lineTo(r * 0.9, r * 0.55)
              ..lineTo(r * 1.5, r * 1.5)
              ..strokePath();
          } else {
            // Çarpı
            canvas
              ..moveTo(r * 0.55, r * 0.55)
              ..lineTo(r * 1.45, r * 1.45)
              ..moveTo(r * 0.55, r * 1.45)
              ..lineTo(r * 1.45, r * 0.55)
              ..strokePath();
          }
        },
      ),
    );
  }

  pw.Widget _instructions() => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4),
    decoration: pw.BoxDecoration(
      color: const PdfColor(0.95, 0.95, 0.95),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Row(
      children: [
        pw.Text('Doğru:', style: _text(7.5, bold: true)),
        pw.SizedBox(width: 3),
        _sample(good: true, kind: 0),
        pw.SizedBox(width: 8),
        pw.Text('Yanlış:', style: _text(7.5, bold: true)),
        pw.SizedBox(width: 3),
        _sample(good: false, kind: 0),
        pw.SizedBox(width: 2),
        _sample(good: false, kind: 1),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            'Yuvarlağı kurşun kalemle tamamen doldurun. Silerken iz bırakmayın. '
            'Öğrenci numaranızı kutulara yazıp altındaki rakamları işaretleyin.',
            style: _text(7),
          ),
        ),
      ],
    ),
  );

  pw.Widget _bubble(Bubble b) => _at(
    b.bounds,
    pw.Container(
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: _bubbleInk, width: 0.6),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(b.label, style: _text(6, color: _labelInk)),
    ),
  );

  List<pw.Widget> _openBox(OpenBox o) {
    final q = o.question;
    final lines = (o.answerRect.height / FormLayout.answerLineHeight).floor();
    return [
      _at(
        o.titleRect,
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            '${q.number}. Soru  (${fmtNum(q.maxPoints)} puan)',
            style: _text(9.5, bold: true),
          ),
        ),
      ),
      _at(
        o.scoreRect,
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _bubbleInk, width: 0.6),
            borderRadius: pw.BorderRadius.circular(2),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 3),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '/ ${fmtNum(q.maxPoints)}',
            style: _text(7.5, color: _bubbleInk),
          ),
        ),
      ),
      if (o.promptRect.height > 0)
        _at(
          o.promptRect,
          pw.Text(
            q.prompt.trim(),
            style: _text(9),
            overflow: pw.TextOverflow.clip,
          ),
        ),
      _at(
        o.answerRect,
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _ink, width: 0.8),
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Column(
            children: [
              for (var i = 1; i < lines; i++)
                pw.Container(
                  height: mm(FormLayout.answerLineHeight),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _guideInk, width: 0.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }
}
