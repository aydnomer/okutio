/// Testler için yapay "telefon fotoğrafı" üretir: formu çizer, öğrencinin
/// işaretlerini ekler, sonra eğik çekim, karanlık, gölge ve gürültü uygular.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:okutio/core/form/form_layout.dart';
import 'package:okutio/core/scan/gray_image.dart';
import 'package:okutio/core/scan/homography.dart';
import 'package:zxing2/qrcode.dart';

class StudentMarks {
  StudentMarks({
    this.choices = const {},
    this.studentNumber = '',
    this.booklet,
    this.faint = const {},
  });

  /// Soru numarası → işaretlenen şıklar.
  final Map<int, Set<int>> choices;

  /// Örn. "1234" → sağa yaslanmış, baştaki haneler 0.
  final String studentNumber;
  final int? booklet;

  /// Silik (yarım silinmiş) işaretler: soru → şık.
  final Map<int, int> faint;
}

class Camera {
  const Camera({
    this.brightness = 1.0,
    this.shadow = 0.0,
    this.noise = 0.0,
    this.tilt = 0.0,
    this.rotation = 0.0,
    this.blur = 0,
    this.upsideDown = false,
    this.width = 1500,
    this.height = 2000,
    this.seed = 1,
    this.zoom = 1,
  });

  /// 1 normal; 0.25 çok karanlık oda.
  final double brightness;

  /// 0-1: kâğıdın bir yanına düşen gölgenin koyuluğu.
  final double shadow;

  /// Piksel gürültüsünün standart sapması (0-255 ölçeğinde).
  final double noise;

  /// Perspektif: üst kenarın alt kenara göre ne kadar dar olduğu (0-0.3).
  final double tilt;

  /// Derece.
  final double rotation;
  final int blur;
  final bool upsideDown;
  final int width;
  final int height;
  final int seed;

  /// 1'den büyükse kâğıt kadraja sığmaz (köşeler dışarıda kalır).
  final double zoom;
}

const _pxPerMm = 6.0;

/// Formu düz olarak çizer (gri tonlu).
GrayImage renderSheet(FormPage page, StudentMarks marks) {
  final w = (FormLayout.pageWidth * _pxPerMm).round();
  final h = (FormLayout.pageHeight * _pxPerMm).round();
  final g = GrayImage(w, h)..data.fillRange(0, w * h, 250);

  void rect(MmRect r, int v, {bool fill = true, double stroke = 0.3}) {
    final x0 = (r.left * _pxPerMm).round(), x1 = (r.right * _pxPerMm).round();
    final y0 = (r.top * _pxPerMm).round(), y1 = (r.bottom * _pxPerMm).round();
    final s = math.max(1, (stroke * _pxPerMm).round());
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final edge = x < x0 + s || x >= x1 - s || y < y0 + s || y >= y1 - s;
        if (fill || edge) g.data[y * w + x] = v;
      }
    }
  }

  void circle(
    Bubble b, {
    required int v,
    required bool fill,
    double fillR = 1,
  }) {
    final cx = b.cx * _pxPerMm, cy = b.cy * _pxPerMm;
    final r = FormLayout.bubbleRadius * _pxPerMm;
    for (var y = (cy - r - 1).floor(); y <= (cy + r + 1).ceil(); y++) {
      for (var x = (cx - r - 1).floor(); x <= (cx + r + 1).ceil(); x++) {
        final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
        if (fill ? d <= r * fillR : (d <= r && d >= r - 0.6 * 0.6 * _pxPerMm)) {
          g.data[y * w + x] = v;
        }
      }
    }
  }

  for (final m in page.markers) {
    rect(m, 10);
  }
  // QR
  final code = Encoder.encode(page.qrPayload, ErrorCorrectionLevel.m);
  final matrix = code.matrix!;
  const quiet = 0;
  final modules = matrix.width + quiet * 2;
  final cell = page.qr.width / modules;
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) == 1) {
        rect(
          MmRect(
            page.qr.left + (x + quiet) * cell,
            page.qr.top + (y + quiet) * cell,
            cell,
            cell,
          ),
          10,
        );
      }
    }
  }
  // Başlık yazısını taklit eden koyu çizgiler.
  rect(MmRect(page.header.left, page.header.top + 1, 90, 4), 30);
  rect(page.nameBox, 30, fill: false);
  // Öğrencinin adı (el yazısı taklidi).
  rect(MmRect(page.nameBox.left + 5, page.nameBox.top + 5, 40, 1), 60);

  final allBubbles = <Bubble>[
    for (final d in page.studentNumber) ...d.bubbles,
    ...page.bookletBubbles,
    for (final r in page.choiceRows) ...r.bubbles,
  ];
  for (final b in allBubbles) {
    circle(b, v: 120, fill: false);
    // Yuvarlağın içindeki açık gri harf.
    final cx = b.cx * _pxPerMm, cy = b.cy * _pxPerMm;
    for (var y = (cy - 3).round(); y < (cy + 3).round(); y++) {
      g.data[y * w + cx.round()] = 160;
    }
  }
  for (final r in page.choiceRows) {
    rect(MmRect(r.labelRect.left + 3, r.labelRect.top + 1, 3, 3), 20);
  }
  for (final o in page.openBoxes) {
    rect(o.answerRect, 20, fill: false);
    rect(MmRect(o.titleRect.left, o.titleRect.top + 1, 30, 3), 25);
    // Öğrencinin el yazısı.
    for (var line = 0; line < 3; line++) {
      rect(
        MmRect(
          o.answerRect.left + 5,
          o.answerRect.top + 4 + line * 7,
          120 - line * 25,
          1.2,
        ),
        50,
      );
    }
  }

  // Öğrencinin işaretleri: kurşun kalem, tam dolmayan, biraz taşan.
  final rnd = math.Random(7);
  void pencil(Bubble b, int darkness) => circle(
    b,
    v: darkness + rnd.nextInt(30),
    fill: true,
    fillR: 0.85 + rnd.nextDouble() * 0.2,
  );

  marks.choices.forEach((q, opts) {
    final row = page.choiceRows.where((r) => r.number == q);
    if (row.isEmpty) return;
    for (final o in opts) {
      pencil(row.single.bubbles[o], 45);
    }
  });
  marks.faint.forEach((q, o) {
    final row = page.choiceRows.where((r) => r.number == q);
    if (row.isEmpty) return;
    circle(row.single.bubbles[o], v: 175, fill: true, fillR: 0.9);
  });
  final digits = marks.studentNumber.padLeft(page.studentNumber.length, '0');
  for (
    var i = 0;
    i < page.studentNumber.length && marks.studentNumber.isNotEmpty;
    i++
  ) {
    pencil(page.studentNumber[i].bubbles[int.parse(digits[i])], 40);
  }
  if (marks.booklet != null && page.bookletBubbles.isNotEmpty) {
    pencil(page.bookletBubbles[marks.booklet!], 40);
  }
  return g;
}

/// Düz formu "telefonla çekilmiş" gibi gösterir ve JPEG baytlarını döner.
Uint8List photograph(GrayImage sheet, Camera cam) {
  final rnd = math.Random(cam.seed);
  final W = cam.width, H = cam.height;
  // Kâğıdın fotoğraftaki dört köşesi.
  final cx = W / 2, cy = H / 2;
  final pageH = H * 0.86 * cam.zoom;
  final pageW = pageH * FormLayout.pageWidth / FormLayout.pageHeight;
  final topW = pageW * (1 - cam.tilt);
  var corners = [
    Point2(cx - topW / 2, cy - pageH / 2),
    Point2(cx + topW / 2, cy - pageH / 2),
    Point2(cx + pageW / 2, cy + pageH / 2),
    Point2(cx - pageW / 2, cy + pageH / 2),
  ];
  final a = cam.rotation * math.pi / 180;
  corners = [
    for (final p in corners)
      Point2(
        cx + (p.x - cx) * math.cos(a) - (p.y - cy) * math.sin(a),
        cy + (p.x - cx) * math.sin(a) + (p.y - cy) * math.cos(a),
      ),
  ];
  if (cam.upsideDown) {
    corners = [corners[2], corners[3], corners[0], corners[1]];
  }
  final sw = sheet.width.toDouble(), sh = sheet.height.toDouble();
  final toSheet = Homography.fromPoints(corners, [
    const Point2(0, 0),
    Point2(sw, 0),
    Point2(sw, sh),
    Point2(0, sh),
  ])!;

  final out = img.Image(width: W, height: H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      final p = toSheet.map(x.toDouble(), y.toDouble());
      double v;
      if (p.x >= 0 && p.y >= 0 && p.x < sw - 1 && p.y < sh - 1) {
        v = sheet.sample(p.x, p.y);
      } else {
        // Masa: ahşap tonunda, desenli.
        v = 110 + 30 * math.sin(x / 37) * math.cos(y / 53);
      }
      // Işık: genel karanlık + bir yandan düşen gölge.
      final light = cam.brightness * (1 - cam.shadow * (x / W) * (0.5 + y / H));
      v = v * light + rnd.nextDouble() * cam.noise * 2 - cam.noise;
      final c = v.clamp(0, 255).round();
      // Hafif sarı ışık (akkor lamba).
      out.setPixelRgb(x, y, c, (c * 0.97).round(), (c * 0.85).round());
    }
  }
  final finalImg = cam.blur > 0 ? img.gaussianBlur(out, radius: cam.blur) : out;
  return img.encodeJpg(finalImg, quality: 85);
}
