/// Kâğıt düzlemi (mm) ile fotoğraf (piksel) arasındaki perspektif dönüşümü.
library;

import 'dart:math' as math;

class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class Homography {
  Homography._(this._m);

  /// 3×3 matris, satır satır; m[8] = 1.
  final List<double> _m;

  /// Dört nokta eşlemesinden dönüşümü bulur. Noktalar doğrusal ise `null`.
  static Homography? fromPoints(List<Point2> from, List<Point2> to) {
    assert(from.length == 4 && to.length == 4);
    // 8 bilinmeyenli doğrusal sistem: A·h = b
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final (x, y) = (from[i].x, from[i].y);
      final (u, v) = (to[i].x, to[i].y);
      a[2 * i]
        ..setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y])
        ..[8] = u;
      a[2 * i + 1]
        ..setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y])
        ..[8] = v;
    }
    // Kısmi pivotlu Gauss yok etme.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    return Homography._([for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1]);
  }

  Point2 map(double x, double y) {
    final m = _m;
    final w = m[6] * x + m[7] * y + m[8];
    return Point2(
      (m[0] * x + m[1] * y + m[2]) / w,
      (m[3] * x + m[4] * y + m[5]) / w,
    );
  }

  /// Noktanın çevresinde 1 mm'nin kaç piksel tuttuğu (yaklaşık).
  double scaleAt(double x, double y) {
    final p = map(x, y);
    final px = map(x + 1, y);
    final py = map(x, y + 1);
    final dx = (px.x - p.x) * (px.x - p.x) + (px.y - p.y) * (px.y - p.y);
    final dy = (py.x - p.x) * (py.x - p.x) + (py.y - p.y) * (py.y - p.y);
    return (math.sqrt(dx) + math.sqrt(dy)) / 2;
  }
}
