/// Sayıyı Türkçe biçimde, gereksiz sıfırlar olmadan yazar: 2.5 → "2,5", 10.0 → "10".
String fmtNum(double v, {int maxDecimals = 2}) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(maxDecimals);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.replaceAll('.', ',');
}
