/// Tarama için gri tonlu görüntü ve ışık düzeltme.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 0 (siyah) ile 255 (beyaz) arası tek kanallı görüntü.
class GrayImage {
  GrayImage(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List data;

  int at(int x, int y) => data[y * width + x];

  /// Görüntü dışı için beyaz döner (kâğıt kenarı gibi davranır).
  int atSafe(int x, int y) =>
      (x < 0 || y < 0 || x >= width || y >= height) ? 255 : data[y * width + x];

  /// İki doğrusal ara değerleme ile alt piksel okuma.
  double sample(double x, double y) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    final a = atSafe(x0, y0), b = atSafe(x0 + 1, y0);
    final c = atSafe(x0, y0 + 1), d = atSafe(x0 + 1, y0 + 1);
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  }

  /// Renkli görüntüyü gri tona çevirir, uzun kenarı [maxSide]'ı geçmeyecek
  /// şekilde küçültür (hız için; okuma doğruluğunu etkilemez).
  factory GrayImage.fromImage(img.Image source, {int maxSide = 1800}) {
    var src = source;
    final longSide = math.max(src.width, src.height);
    if (longSide > maxSide) {
      final scale = maxSide / longSide;
      src = img.copyResize(
        src,
        width: (src.width * scale).round(),
        height: (src.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    final out = GrayImage(src.width, src.height);
    var i = 0;
    for (final p in src) {
      out.data[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
        0,
        255,
      );
    }
    return out;
  }

  /// JPEG/PNG baytlarından; çözülemezse `null`.
  static GrayImage? decode(Uint8List bytes, {int maxSide = 1800}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Telefon fotoğraflarındaki döndürme bilgisini uygula.
    final oriented = img.bakeOrientation(decoded);
    return GrayImage.fromImage(oriented, maxSide: maxSide);
  }

  /// Ortalama parlaklık (0-255).
  double get mean {
    var sum = 0;
    for (final v in data) {
      sum += v;
    }
    return sum / data.length;
  }

  /// Işık düzeltme: her pikseli çevresinin aydınlığına böler.
  ///
  /// Karanlıkta, gölgede ya da tek taraftan ışık alan fotoğraflarda kâğıt
  /// her yerde beyaza, mürekkep ve kurşun kalem her yerde koyuya çekilir.
  /// [radius] arka planı tahmin etmek için kullanılan pencere yarıçapıdır;
  /// en büyük koyu şekilden (köşe karesi) büyük olmalı.
  GrayImage normalizeLighting({int? radius}) {
    final r = radius ?? math.max(8, (math.max(width, height) / 40).round());
    // Arka plan: koyu nesneleri yok saymak için önce "maksimum" süzgeci
    // (kâğıdın beyazını yayar), sonra yumuşatma.
    final bg = _boxBlur(_maxFilter(this, r), r);
    final out = GrayImage(width, height);
    for (var i = 0; i < data.length; i++) {
      final b = math.max(bg.data[i], 8);
      out.data[i] = math.min(255, data[i] * 255 ~/ b);
    }
    return out;
  }

  /// [MmRect] gibi bir bölgeyi düz bir görüntüye açar.
  GrayImage warp(
    int outW,
    int outH,
    ({double x, double y}) Function(double u, double v) map,
  ) {
    final out = GrayImage(outW, outH);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final p = map(x + 0.5, y + 0.5);
        out.data[y * outW + x] = sample(p.x, p.y).round().clamp(0, 255);
      }
    }
    return out;
  }

  img.Image toImage() {
    // Üç kanallı: tek kanallı JPEG'i bazı tarayıcılar renkli gösteriyor.
    final out = img.Image(width: width, height: height);
    var i = 0;
    for (final p in out) {
      final v = data[i++];
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    return out;
  }
}

/// Ayrılabilir kayan maksimum süzgeci (önce yatay, sonra dikey).
GrayImage _maxFilter(GrayImage src, int r) {
  final w = src.width, h = src.height;
  final tmp = Uint8List(w * h);
  final out = GrayImage(w, h);
  // Büyük pencerede hızlı olsun diye küçültülmüş çözünürlükte çalışmak yerine
  // basit ama doğrusal zamanlı van Herk/Gil-Werman yaklaşımı.
  _slidingMax(src.data, tmp, w, h, r, horizontal: true);
  _slidingMax(tmp, out.data, w, h, r, horizontal: false);
  return out;
}

void _slidingMax(
  Uint8List src,
  Uint8List dst,
  int w,
  int h,
  int r, {
  required bool horizontal,
}) {
  final n = horizontal ? w : h;
  final lines = horizontal ? h : w;
  final win = 2 * r + 1;
  final line = Uint8List(n);
  final g = Uint8List(n);
  final hh = Uint8List(n);
  for (var l = 0; l < lines; l++) {
    for (var i = 0; i < n; i++) {
      line[i] = horizontal ? src[l * w + i] : src[i * w + l];
    }
    for (var i = 0; i < n; i++) {
      g[i] = (i % win == 0) ? line[i] : math.max(g[i - 1], line[i]);
    }
    for (var i = n - 1; i >= 0; i--) {
      hh[i] = (i == n - 1 || (i + 1) % win == 0)
          ? line[i]
          : math.max(hh[i + 1], line[i]);
    }
    for (var i = 0; i < n; i++) {
      final a = math.max(0, i - r);
      final b = math.min(n - 1, i + r);
      final v = math.max(hh[a], g[b]);
      if (horizontal) {
        dst[l * w + i] = v;
      } else {
        dst[i * w + l] = v;
      }
    }
  }
}

/// Toplamlı tablo ile kutu bulanıklaştırma.
GrayImage _boxBlur(GrayImage src, int r) {
  final w = src.width, h = src.height;
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0;
    for (var x = 0; x < w; x++) {
      rowSum += src.data[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] =
          integral[y * (w + 1) + x + 1] + rowSum;
    }
  }
  final out = GrayImage(w, h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
      final sum =
          integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      out.data[y * w + x] = (sum / ((x1 - x0) * (y1 - y0))).round();
    }
  }
  return out;
}
