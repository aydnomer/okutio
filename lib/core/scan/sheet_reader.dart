/// Fotoğrafı çekilmiş ya da taranmış bir optik formu okur.
///
/// Adımlar:
/// 1. Işık düzeltme (karanlık, gölgeli, sarı ışıklı fotoğraflar için).
/// 2. Dört köşe karesini bulma ve perspektifi düzeltme (eğik çekim).
/// 3. QR kodu çözme (hangi sınav, hangi sayfa).
/// 4. Her yuvarlağın ne kadar dolu olduğunu ölçme.
/// 5. Emin olunamayan soruları öğretmene işaretleme.
///
/// Tamamen cihazda çalışır; internet gerekmez, öğrenci verisi dışarı çıkmaz.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../form/form_layout.dart';
import 'gray_image.dart';
import 'homography.dart';

/// Bir yuvarlağın okunuşu.
enum MarkState { empty, filled, unsure }

class BubbleReading {
  const BubbleReading(this.darkness, this.state);

  /// 0 (bembeyaz) – 1 (simsiyah).
  final double darkness;
  final MarkState state;
}

class ChoiceReading {
  const ChoiceReading(this.number, this.bubbles);

  /// Formdaki soru numarası.
  final int number;
  final List<BubbleReading> bubbles;

  Set<int> get marked => {
    for (var i = 0; i < bubbles.length; i++)
      if (bubbles[i].state == MarkState.filled) i,
  };

  /// Öğretmenin bir göz atması gereken durum: silik işaret.
  bool get unsure => bubbles.any((b) => b.state == MarkState.unsure);
}

/// Açık uçlu sorunun, perspektifi düzeltilmiş cevap görüntüsü.
class OpenAnswerImage {
  const OpenAnswerImage(this.questionNumber, this.jpeg);

  final int questionNumber;

  /// Gri tonlu, ışığı düzeltilmiş JPEG.
  final Uint8List jpeg;
}

class SheetReading {
  SheetReading({
    required this.page,
    required this.choices,
    required this.studentDigits,
    required this.bookletIndex,
    required this.qrText,
    required this.openAnswers,
    required this.warnings,
    required this.markerCenters,
    this.answerArea,
  });

  final FormPage page;
  final List<ChoiceReading> choices;

  /// Her hane için okunan rakam; okunamayanlar `null`.
  final List<int?> studentDigits;

  /// İşaretlenen kitapçık (0 = A); yoksa ya da çoklu ise `null`.
  final int? bookletIndex;

  /// QR çözülebildiyse metni.
  final String? qrText;

  final List<OpenAnswerImage> openAnswers;

  /// Öğretmene gösterilecek, Türkçe uyarılar.
  final List<String> warnings;

  /// Fotoğrafta bulunan köşe kareleri (sol üst, sağ üst, sağ alt, sol alt).
  final List<Point2> markerCenters;

  /// Fotoğrafın düzeltilmiş işaret alanı (numara, kitapçık ve test soruları).
  /// Öğretmene işaretlerin üstüne yeşil/kırmızı halka çizerek gösterilir.
  /// Bölge [FormPage.answerArea] ile aynıdır, ölçek [answerAreaPxPerMm].
  final Uint8List? answerArea;

  static const answerAreaPxPerMm = 4.0;

  /// Öğrenci numarası; okunamayan haneler "?" olur, baştaki boş haneler atılır.
  String get studentNumber {
    final s = studentDigits.map((d) => d?.toString() ?? '?').join();
    final trimmed = s.replaceFirst(RegExp('^0+'), '');
    return trimmed.isEmpty ? (s.contains('0') ? '0' : '') : trimmed;
  }

  bool get studentNumberComplete =>
      studentDigits.isNotEmpty && studentDigits.every((d) => d != null);

  List<int> get unsureQuestions => [
    for (final c in choices)
      if (c.unsure) c.number,
  ];
}

/// Okuma başarısız olduğunda öğretmene ne yapması gerektiğini söyler.
class ScanFailure implements Exception {
  const ScanFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class SheetReader {
  const SheetReader(this.layout);

  final FormLayout layout;

  /// Bu koyuluğun üstü işaretli sayılır.
  static const filledThreshold = 0.38;

  /// Bu aralık "silik": öğretmene sorulur.
  static const unsureThreshold = 0.24;

  SheetReading readBytes(Uint8List bytes, {int pageIndex = 0}) {
    final gray = GrayImage.decode(bytes);
    if (gray == null) {
      throw const ScanFailure(
        'Fotoğraf açılamadı. JPEG ya da PNG biçiminde bir fotoğraf seçin.',
      );
    }
    return read(gray, pageIndex: pageIndex);
  }

  SheetReading read(GrayImage photo, {int pageIndex = 0}) {
    final warnings = <String>[];
    if (photo.mean < 60) {
      warnings.add(
        'Fotoğraf çok karanlık. Okundu ama sonuçlara bir göz atın; '
        'mümkünse daha aydınlık bir yerde çekin.',
      );
    }
    final norm = photo.normalizeLighting();

    final corners = findMarkers(norm);
    if (corners == null) {
      throw const ScanFailure(
        'Kâğıdın dört köşesindeki siyah kareler bulunamadı. '
        'Kâğıdın tamamı görünecek şekilde, biraz daha uzaktan çekin.',
      );
    }

    // Kâğıt ters ya da yan çekilmiş olabilir: dört yönü dene, QR'ın
    // olduğu köşeyi en koyu bulan yönü seç.
    FormPage pageFor(int index) =>
        layout.pages[index.clamp(0, layout.pages.length - 1)];
    var page = pageFor(pageIndex);
    final mmCorners = [
      for (final m in [0, 1, 3, 2]) // sol üst, sağ üst, sağ alt, sol alt
        Point2(
          page.markers[m].left + page.markers[m].width / 2,
          page.markers[m].top + page.markers[m].height / 2,
        ),
    ];
    Homography? best;
    var bestScore = -1.0;
    for (var rot = 0; rot < 4; rot++) {
      final rotated = [for (var i = 0; i < 4; i++) corners[(i + rot) % 4]];
      final h = Homography.fromPoints(mmCorners, rotated);
      if (h == null || !_markersMatch(norm, h, page)) continue;
      final score =
          _regionDarkness(norm, h, page.qr) -
          _regionDarkness(norm, h, _mirror(page.qr));
      if (score > bestScore) {
        bestScore = score;
        best = h;
      }
    }
    if (best == null) {
      throw const ScanFailure(
        'Kâğıdın dört köşesi net görünmüyor ya da kâğıt çok eğik. '
        'Telefonu kâğıda paralel tutun, dört köşedeki siyah kareler de '
        'kadraja girsin.',
      );
    }
    final h = best;

    final qrText = _decodeQr(norm, h, page.qr);
    if (qrText != null) {
      final parsed = FormLayout.parsePayload(qrText);
      if (parsed == null) {
        warnings.add('Bu kâğıttaki QR kod Okutio formuna ait değil.');
      } else if (parsed.examId != layout.exam.id) {
        throw const ScanFailure(
          'Bu kâğıt başka bir sınava ait. Doğru sınavı seçip tekrar deneyin.',
        );
      } else if (parsed.page != page.index &&
          parsed.page < layout.pages.length) {
        // Başka bir sayfa okutuldu: o sayfanın yerleşimiyle oku.
        page = pageFor(parsed.page);
      }
    }

    final scale = h.scaleAt(page.qr.left, page.qr.top);
    if (scale < 2.2) {
      warnings.add(
        'Kâğıt fotoğrafta küçük kalmış. Daha yakından çekerseniz okuma güvenilir olur.',
      );
    }

    final choices = [
      for (final row in page.choiceRows)
        ChoiceReading(row.number, _readGroup(norm, h, row.bubbles)),
    ];

    final digits = <int?>[];
    for (final col in page.studentNumber) {
      final r = _readGroup(norm, h, col.bubbles);
      final filled = [
        for (var i = 0; i < r.length; i++)
          if (r[i].state == MarkState.filled) i,
      ];
      digits.add(filled.length == 1 ? filled.single : null);
    }

    int? booklet;
    if (page.bookletBubbles.isNotEmpty) {
      final r = _readGroup(norm, h, page.bookletBubbles);
      final filled = [
        for (var i = 0; i < r.length; i++)
          if (r[i].state == MarkState.filled) i,
      ];
      if (filled.length == 1) booklet = filled.single;
    }

    final open = [
      for (final box in page.openBoxes)
        OpenAnswerImage(
          box.question.number,
          _cropJpeg(norm, h, box.answerRect, pxPerMm: 5),
        ),
    ];

    final area = page.answerArea;
    return SheetReading(
      page: page,
      choices: choices,
      studentDigits: digits,
      bookletIndex: booklet,
      qrText: qrText,
      openAnswers: open,
      warnings: warnings,
      markerCenters: corners,
      answerArea: area == null
          ? null
          : _cropJpeg(
              norm,
              h,
              area,
              pxPerMm: SheetReading.answerAreaPxPerMm,
              quality: 65,
            ),
    );
  }

  // ---- Köşe kareleri ----

  /// Fotoğraftaki dört köşe karesinin merkezleri: sol üst, sağ üst,
  /// sağ alt, sol alt (fotoğrafa göre). Bulunamazsa `null`.
  static List<Point2>? findMarkers(GrayImage norm) {
    // Köşe kareleri beyaz kâğıdın üstünde durur: çevresi aydınlık olmayan
    // şekiller (masa deseni, gölge, kitap) elenir.
    final blobs = _darkBlobs(norm).where((b) => _onWhite(norm, b)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final top = blobs.take(8).toList();
    if (top.length < 4) return null;

    // Dört şeklin her birleşimini dene: benzer büyüklükte, dışbükey, kâğıt
    // oranına (en/boy ≈ 0,68) yakın ve en geniş alanı kaplayan dörtlüyü seç.
    List<Point2>? best;
    var bestArea = 0.0;
    final minSide = math.min(norm.width, norm.height) * 0.25;
    for (var a = 0; a < top.length; a++) {
      for (var b = a + 1; b < top.length; b++) {
        for (var c = b + 1; c < top.length; c++) {
          for (var d = c + 1; d < top.length; d++) {
            final quad = [top[a], top[b], top[c], top[d]];
            final counts = quad.map((q) => q.count);
            if (counts.reduce(math.max) > 3.5 * counts.reduce(math.min)) {
              continue;
            }
            final pts = _ordered([for (final q in quad) Point2(q.cx, q.cy)]);
            if (!_convex(pts)) continue;
            final sides = [
              for (var i = 0; i < 4; i++) _dist(pts[i], pts[(i + 1) % 4]),
            ];
            if (sides.reduce(math.min) < minSide) continue;
            final w = (sides[0] + sides[2]) / 2, h = (sides[1] + sides[3]) / 2;
            final ratio = math.min(w, h) / math.max(w, h);
            if (ratio < 0.45 || ratio > 0.9) continue;
            final area = _area(pts);
            if (area > bestArea) {
              bestArea = area;
              best = pts;
            }
          }
        }
      }
    }
    return best;
  }

  static double _dist(Point2 a, Point2 b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  static double _area(List<Point2> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// Noktaları merkez çevresinde saat yönünde sıralar, sol üstteki başta.
  static List<Point2> _ordered(List<Point2> pts) {
    final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / 4;
    final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / 4;
    final sorted = [...pts]
      ..sort(
        (a, b) => math
            .atan2(a.y - cy, a.x - cx)
            .compareTo(math.atan2(b.y - cy, b.x - cx)),
      );
    var start = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) {
        start = i;
      }
    }
    return [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
  }

  /// Şeklin çevresindeki halkanın büyük kısmı beyaz mı?
  static bool _onWhite(GrayImage norm, _Blob b) {
    final r = math.sqrt(b.count) / 2 * 1.9;
    const n = 36;
    var bright = 0;
    for (var i = 0; i < n; i++) {
      final t = 2 * math.pi * i / n;
      if (norm.sample(b.cx + r * math.cos(t), b.cy + r * math.sin(t)) > 170) {
        bright++;
      }
    }
    return bright >= n * 0.85;
  }

  static bool _convex(List<Point2> p) {
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-6) return false;
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return true;
  }

  /// Hata ayıklama için: bulunan koyu şekiller (alan, x, y).
  static List<(int, double, double)> debugBlobs(GrayImage norm) => [
    for (final b in _darkBlobs(norm)) (b.count, b.cx, b.cy),
  ];

  static List<_Blob> _darkBlobs(GrayImage norm) {
    final w = norm.width, h = norm.height;
    final dark = Uint8List(w * h);
    for (var i = 0; i < dark.length; i++) {
      if (norm.data[i] < 110) dark[i] = 1;
    }
    final minArea = math.max(12, (w * h) ~/ 60000);
    final blobs = <_Blob>[];
    final queue = Queue<int>();
    for (var start = 0; start < dark.length; start++) {
      if (dark[start] != 1) continue;
      dark[start] = 2;
      queue.add(start);
      var count = 0, sx = 0, sy = 0;
      var minX = w, minY = h, maxX = 0, maxY = 0;
      while (queue.isNotEmpty) {
        final i = queue.removeFirst();
        final x = i % w, y = i ~/ w;
        count++;
        sx += x;
        sy += y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x > 0 && dark[i - 1] == 1) {
          dark[i - 1] = 2;
          queue.add(i - 1);
        }
        if (x < w - 1 && dark[i + 1] == 1) {
          dark[i + 1] = 2;
          queue.add(i + 1);
        }
        if (y > 0 && dark[i - w] == 1) {
          dark[i - w] = 2;
          queue.add(i - w);
        }
        if (y < h - 1 && dark[i + w] == 1) {
          dark[i + w] = 2;
          queue.add(i + w);
        }
      }
      if (count < minArea) continue;
      final bw = maxX - minX + 1, bh = maxY - minY + 1;
      final aspect = bw / bh;
      final fill = count / (bw * bh);
      // Dolu, kareye yakın şekiller. Döndürülmüş bir kare kutusunun
      // yaklaşık %50'sini doldurur; içi boş çerçeveler ve yazılar elenir.
      if (aspect < 0.4 || aspect > 2.5 || fill < 0.5) continue;
      // Kâğıt kenarındaki gölge gibi devasa şekiller köşe karesi olamaz.
      if (count > w * h * 0.02) continue;
      blobs.add(_Blob(count, sx / count, sy / count));
    }
    return blobs;
  }

  // ---- Okuma ----

  /// Bulunan şekiller gerçekten köşe kareleri mi? Dönüşümle tahmin edilen
  /// 7 mm'lik karelerin içi koyu, hemen dışı beyaz olmalı. Yanlış şekiller
  /// (ör. kâğıt kadrajdan taşınca seçilen yuvarlaklar) burada elenir.
  static bool _markersMatch(GrayImage norm, Homography h, FormPage page) {
    for (final m in page.markers) {
      final inner = MmRect(
        m.left + m.width * 0.15,
        m.top + m.height * 0.15,
        m.width * 0.7,
        m.height * 0.7,
      );
      if (_regionDarkness(norm, h, inner, step: 0.7) < 0.55) return false;
      const gap = 1.2;
      final ring = [
        MmRect(m.left - gap - 0.6, m.top, 0.6, m.height),
        MmRect(m.right + gap, m.top, 0.6, m.height),
        MmRect(m.left, m.top - gap - 0.6, m.width, 0.6),
        MmRect(m.left, m.bottom + gap, m.width, 0.6),
      ];
      for (final r in ring) {
        if (_regionDarkness(norm, h, r, step: 0.3) > 0.3) return false;
      }
    }
    return true;
  }

  static MmRect _mirror(MmRect r) => MmRect(
    FormLayout.pageWidth - r.right,
    FormLayout.pageHeight - r.bottom,
    r.width,
    r.height,
  );

  static double _regionDarkness(
    GrayImage norm,
    Homography h,
    MmRect r, {
    double step = 1,
  }) {
    var sum = 0.0;
    var n = 0;
    for (var y = step / 2; y < r.height; y += step) {
      for (var x = step / 2; x < r.width; x += step) {
        final p = h.map(r.left + x, r.top + y);
        sum += 1 - norm.sample(p.x, p.y) / 255;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Yuvarlağın iç kısmının ortalama koyuluğu. Kenar çizgisi hariç tutulur.
  static double bubbleDarkness(GrayImage norm, Homography h, Bubble b) {
    const inner = FormLayout.bubbleRadius * 0.62;
    var sum = 0.0;
    var n = 0;
    const steps = 6;
    for (var i = -steps; i <= steps; i++) {
      for (var j = -steps; j <= steps; j++) {
        final dx = inner * i / steps, dy = inner * j / steps;
        if (dx * dx + dy * dy > inner * inner) continue;
        final p = h.map(b.cx + dx, b.cy + dy);
        sum += 1 - norm.sample(p.x, p.y) / 255;
        n++;
      }
    }
    return sum / n;
  }

  List<BubbleReading> _readGroup(
    GrayImage norm,
    Homography h,
    List<Bubble> bubbles,
  ) {
    final d = [for (final b in bubbles) bubbleDarkness(norm, h, b)];
    // Gruptaki boş yuvarlakların koyuluğu (harf baskısı, kâğıt dokusu)
    // taban kabul edilir: soluk baskılı formlar da doğru okunur.
    final sorted = [...d]..sort();
    final base = sorted.first;
    final readings = <BubbleReading>[];
    for (final v in d) {
      final rel = v - base;
      final MarkState state;
      if (v >= filledThreshold && rel >= 0.2) {
        state = MarkState.filled;
      } else if (v >= unsureThreshold && rel >= 0.12) {
        state = MarkState.unsure;
      } else {
        state = MarkState.empty;
      }
      readings.add(BubbleReading(v, state));
    }
    // Biri belirgin dolu, diğeri silikse: silik olan büyük olasılıkla
    // silinmiş eski işarettir. Öğretmene yine de gösterilsin diye
    // "unsure" bırakılır; puanlamada dolu olan esas alınır.
    return readings;
  }

  static String? _decodeQr(GrayImage norm, Homography h, MmRect qr) {
    // QR'ı çevresiyle birlikte düz bir görüntüye aç ve çöz.
    const margin = 3.0;
    const pxPerMm = 10.0;
    final area = MmRect(
      qr.left - margin,
      qr.top - margin,
      qr.width + 2 * margin,
      qr.height + 2 * margin,
    );
    final w = (area.width * pxPerMm).round();
    final hh = (area.height * pxPerMm).round();
    final flat = norm.warp(w, hh, (u, v) {
      final p = h.map(area.left + u / pxPerMm, area.top + v / pxPerMm);
      return (x: p.x, y: p.y);
    });
    final pixels = Int32List(w * hh);
    for (var i = 0; i < pixels.length; i++) {
      final v = flat.data[i];
      pixels[i] = 0xFF000000 | (v << 16) | (v << 8) | v;
    }
    final source = RGBLuminanceSource(w, hh, pixels);
    for (final binarizer in [
      HybridBinarizer(source),
      GlobalHistogramBinarizer(source),
    ]) {
      try {
        return QRCodeReader().decode(BinaryBitmap(binarizer)).text;
      } on Object {
        continue;
      }
    }
    return null;
  }

  static Uint8List _cropJpeg(
    GrayImage norm,
    Homography h,
    MmRect r, {
    required double pxPerMm,
    int quality = 75,
  }) {
    final w = (r.width * pxPerMm).round();
    final hh = (r.height * pxPerMm).round();
    final flat = norm.warp(w, hh, (u, v) {
      final p = h.map(r.left + u / pxPerMm, r.top + v / pxPerMm);
      return (x: p.x, y: p.y);
    });
    return img.encodeJpg(flat.toImage(), quality: quality);
  }
}

class _Blob {
  _Blob(this.count, this.cx, this.cy);

  final int count;
  final double cx;
  final double cy;
}
