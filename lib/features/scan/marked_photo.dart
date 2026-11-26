import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/form/form_layout.dart';
import '../../core/models/booklet.dart';
import '../../core/models/exam.dart';
import '../../core/scan/sheet_reader.dart';

/// Öğrencinin kâğıdının fotoğrafı; işaretlerin üstünde doğrular yeşil,
/// yanlışlar kırmızı halka, kaçırılan doğru cevap da yeşil kesik halka.
///
/// Halkalar kayıtlı fotoğrafa değil o anki puanlamaya göre çizilir; öğretmen
/// bir işareti düzeltirse ya da soruyu iptal ederse fotoğraf da hemen değişir.
class MarkedPhoto extends StatelessWidget {
  const MarkedPhoto({
    required this.exam,
    required this.page,
    required this.booklet,
    required this.marks,
    required this.jpeg,
    super.key,
  });

  final Exam exam;
  final FormPage page;
  final Booklet booklet;
  final Map<int, Set<int>> marks;
  final Uint8List jpeg;

  @override
  Widget build(BuildContext context) {
    final area = page.answerArea!;
    final photo = AspectRatio(
      aspectRatio: area.width / area.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(jpeg, fit: BoxFit.fill, gaplessPlayback: true),
          CustomPaint(
            painter: _MarksPainter(
              exam: exam,
              page: page,
              area: area,
              booklet: booklet,
              marks: marks,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Kâğıdın fotoğrafı, doğrular yeşil yanlışlar kırmızı',
      button: true,
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Kâğıdın fotoğrafı'),
                leading: IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              body: InteractiveViewer(maxScale: 5, child: Center(child: photo)),
            ),
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: photo),
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({
    required this.exam,
    required this.page,
    required this.area,
    required this.booklet,
    required this.marks,
  });

  final Exam exam;
  final FormPage page;
  final MmRect area;
  final Booklet booklet;
  final Map<int, Set<int>> marks;

  static final green = Colors.green.shade600;
  static final red = Colors.red.shade600;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / area.width;
    final r = (FormLayout.bubbleRadius + 0.9) * k;
    final stroke = _max(0.8 * k, 2);
    Offset at(Bubble b) =>
        Offset((b.cx - area.left) * k, (b.cy - area.top) * k);

    final solid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final row in page.choiceRows) {
      if (row.number > exam.choiceCount) continue;
      final master = booklet.masterNumberOf(row.number);
      final q = exam.choiceQuestions[master - 1];
      final marked = marks[row.number] ?? const <int>{};
      if (q.cancelled) {
        for (final o in marked) {
          canvas.drawCircle(
            at(row.bubbles[o]),
            r,
            solid..color = Colors.grey.shade600,
          );
        }
        continue;
      }
      final correct = {
        for (final o in q.correctOptions) booklet.bookletOptionOf(master, o),
      };
      final single = marked.length == 1;
      for (var o = 0; o < row.bubbles.length; o++) {
        final c = at(row.bubbles[o]);
        if (marked.contains(o)) {
          final ok = single && correct.contains(o);
          canvas.drawCircle(c, r, solid..color = ok ? green : red);
        } else if (correct.contains(o)) {
          _dashed(canvas, c, r, green, stroke * 0.8);
        }
      }
      // Satırın solunda küçük sonuç işareti: ✓ doğru, ✗ yanlış, – boş.
      final label = Offset(
        (row.labelRect.left - area.left) * k,
        (row.bubbles.first.cy - area.top) * k,
      );
      final dot = Paint()
        ..color = marked.isEmpty
            ? Colors.grey.shade500
            : single && correct.contains(marked.first)
            ? green
            : red;
      canvas.drawCircle(label + Offset(-r * 0.2, 0), r * 0.35, dot);
    }
  }

  static double _max(double a, double b) => a > b ? a : b;

  void _dashed(Canvas canvas, Offset c, double r, Color color, double w) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = color;
    const n = 12;
    const sweep = 3.14159265 * 2 / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * sweep,
        sweep * 0.55,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) =>
      old.marks != marks || old.exam != exam || old.booklet != booklet;
}

/// Kayıtlı görüntülerden işaret alanı fotoğrafını ayırır: açık uçlu
/// görüntülerden sonra gelen fazladan görüntüdür.
Uint8List? answerAreaImage(List<Uint8List> images, int openImageCount) =>
    images.length > openImageCount ? images.last : null;

/// Okunan kâğıdın kaydedilecek görüntüleri: önce açık uçlu cevaplar, en sonda
/// işaret alanı.
List<Uint8List> imagesToStore(SheetReading reading) => [
  for (final o in reading.openAnswers) o.jpeg,
  ?reading.answerArea,
];
