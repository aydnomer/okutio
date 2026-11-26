import 'package:material_ui/material_ui.dart';

import '../../core/form/form_layout.dart';

/// Formun ekrandaki küçük önizlemesi. PDF ile aynı yerleşimi çizer;
/// PDF görüntüleyiciye ihtiyaç duymaz, internetsiz de çalışır.
class FormPreview extends StatelessWidget {
  const FormPreview({required this.page, super.key});

  final FormPage page;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Formun önizlemesi, sayfa ${page.index + 1}',
      child: AspectRatio(
        aspectRatio: FormLayout.pageWidth / FormLayout.pageHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                blurRadius: 12,
                offset: Offset(0, 4),
                color: Color(0x33000000),
              ),
            ],
          ),
          child: CustomPaint(painter: _FormPainter(page)),
        ),
      ),
    );
  }
}

class _FormPainter extends CustomPainter {
  _FormPainter(this.page);

  final FormPage page;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / FormLayout.pageWidth;
    Rect r(MmRect m) =>
        Rect.fromLTWH(m.left * k, m.top * k, m.width * k, m.height * k);

    final black = Paint()..color = Colors.black;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.black87;
    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.black38;
    final faint = Paint()..color = const Color(0xFFEAEAEA);

    for (final m in page.markers) {
      canvas.drawRect(r(m), black);
    }
    // QR yerine dama deseni: önizlemede okunması gerekmiyor.
    final qr = r(page.qr);
    final cell = qr.width / 7;
    for (var y = 0; y < 7; y++) {
      for (var x = 0; x < 7; x++) {
        if ((x * 3 + y * 5 + x * y) % 3 == 0 ||
            (x < 2 && y < 2) ||
            (x > 4 && y < 2) ||
            (x < 2 && y > 4)) {
          canvas.drawRect(
            Rect.fromLTWH(qr.left + x * cell, qr.top + y * cell, cell, cell),
            black,
          );
        }
      }
    }
    // Başlık: kalın bir çizgi ve ince bir çizgi.
    final h = r(page.header);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(h.left, h.top, h.width * 0.7, h.height * 0.35),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.black87,
      )
      ..drawRect(
        Rect.fromLTWH(
          h.left,
          h.top + h.height * 0.55,
          h.width * 0.4,
          h.height * 0.15,
        ),
        Paint()..color = Colors.black45,
      );
    final name = r(page.nameBox);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(name.left, name.top, name.width * 0.74, name.height),
          const Radius.circular(3),
        ),
        line,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            name.left + name.width * 0.76,
            name.top,
            name.right,
            name.bottom,
          ),
          const Radius.circular(3),
        ),
        line,
      );
    if (page.instructions case final i?) {
      canvas.drawRect(r(i), faint);
    }

    for (final f in [page.studentNumberFrame, page.bookletFrame]) {
      if (f != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r(f), const Radius.circular(3)),
          line,
        );
      }
    }
    void bubble(Bubble b) => canvas.drawCircle(
      Offset(b.cx * k, b.cy * k),
      FormLayout.bubbleRadius * k,
      light,
    );
    for (final d in page.studentNumber) {
      canvas.drawRect(r(d.writeBox), light);
      d.bubbles.forEach(bubble);
    }
    page.bookletBubbles.forEach(bubble);
    for (final row in page.choiceRows) {
      final l = r(row.labelRect);
      canvas.drawRect(
        Rect.fromLTWH(
          l.right - l.width * 0.45,
          l.center.dy - 1,
          l.width * 0.4,
          2,
        ),
        Paint()..color = Colors.black87,
      );
      row.bubbles.forEach(bubble);
    }
    for (final o in page.openBoxes) {
      final t = r(o.titleRect);
      canvas
        ..drawRect(
          Rect.fromLTWH(t.left, t.center.dy - 1.5, t.width * 0.18, 3),
          Paint()..color = Colors.black87,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(r(o.scoreRect), const Radius.circular(2)),
          light,
        );
      if (o.promptRect.height > 0) {
        final p = r(o.promptRect);
        canvas.drawRect(
          Rect.fromLTWH(p.left, p.top + 1, p.width * 0.6, 2),
          Paint()..color = Colors.black45,
        );
      }
      final a = r(o.answerRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(a, const Radius.circular(2)),
        line,
      );
      final step = FormLayout.answerLineHeight * k;
      for (var y = a.top + step; y < a.bottom - 1; y += step) {
        canvas.drawLine(Offset(a.left, y), Offset(a.right, y), faint);
      }
    }
  }

  @override
  bool shouldRepaint(_FormPainter old) => old.page != page;
}
