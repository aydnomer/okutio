/// Öğretmenin sesli ya da yazılı söylediği ayar komutlarını anlar.
///
/// Telefonun konuşmayı yazıya çevirdiği Türkçe cümle buraya gelir; internete
/// hiçbir şey gönderilmez. Bir cümlede birden fazla komut olabilir:
/// "5. soruyu iptal et, herkese doğru say ve çift işaretleri boş say".
library;

import '../models/exam.dart';
import '../models/scoring_rules.dart';
import '../models/question.dart';

/// Komutun sınava uygulanmış hali ve öğretmene gösterilecek açıklamalar.
class VoiceResult {
  const VoiceResult(this.exam, this.done, this.notUnderstood);

  /// Değişmiş sınav (hiçbir şey anlaşılmadıysa eskisiyle aynı).
  final Exam exam;

  /// "5. soru iptal edildi" gibi, yapılanların listesi.
  final List<String> done;

  /// Anlaşılamayan cümle parçaları.
  final List<String> notUnderstood;

  bool get changed => done.isNotEmpty;
}

class VoiceCommands {
  const VoiceCommands();

  /// Örnek komutlar: yardım ekranında gösterilir.
  static const examples = [
    '5. soruyu iptal et',
    '12. soruyu iptal et, hesaptan çıkar',
    '5. sorunun iptalini kaldır',
    'çift işaretleri boş say',
    '4 yanlış 1 doğruyu götürsün',
    'yanlışlar doğruyu götürmesin',
    '3. sorunun cevabı C',
    '6. sorunun cevabı B ve C',
    'yarım puana yuvarla',
  ];

  VoiceResult apply(Exam exam, String text) {
    var e = exam;
    final done = <String>[];
    final missed = <String>[];
    // "B ve C" gibi çok cevaplı soruları cümle bölünmeden önce birleştir.
    final norm = normalize(text).replaceAllMapped(
      RegExp(r'\b([a-e])\s+(?:ve|ile|veya)\s+([a-e])\b'),
      (m) => '${m[1]}+${m[2]}',
    );
    // Cümle parçalarına ayır ama "herkese doğru say" gibi tamamlayıcıları
    // bir önceki iptal komutuna bağla.
    final parts = norm
        .split(RegExp(r'\s*(?:,|;|(?<!\d)\.|\bve\b|\bsonra\b|\bayrica\b)\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (final part in parts) {
      final r = _one(e, part);
      if (r == null) {
        missed.add(part);
      } else {
        e = r.$1;
        done.add(r.$2);
      }
    }
    return VoiceResult(e, done, missed);
  }

  (Exam, String)? _one(Exam e, String s) {
    // --- Yanlış götürme ---
    if (RegExp(r'gotur(me|mesin|mez|meyecek)').hasMatch(s) ||
        RegExp(r'yanlis\w* .*(etkilemesin|saymasin)').hasMatch(s)) {
      return (
        e.copyWith(rules: e.rules.copyWith(wrongPenaltyDivisor: () => null)),
        'Yanlışlar doğruyu götürmeyecek.',
      );
    }
    final pen = RegExp(r'\b([34]) yanlis\w*\s+(1|bir) dogru').firstMatch(s);
    if (pen != null) {
      final d = int.parse(pen.group(1)!);
      return (
        e.copyWith(rules: e.rules.copyWith(wrongPenaltyDivisor: () => d)),
        '$d yanlış 1 doğruyu götürecek.',
      );
    }

    // --- Çift işaret ---
    if (RegExp(r'(cift|birden fazla|iki) (isaret|sik)').hasMatch(s)) {
      if (RegExp(r'\bbos\b').hasMatch(s)) {
        return (
          e.copyWith(
            rules: e.rules.copyWith(multiMarkPolicy: MultiMarkPolicy.blank),
          ),
          'Çift işaretli sorular boş sayılacak.',
        );
      }
      if (RegExp(r'\byanlis\b').hasMatch(s)) {
        return (
          e.copyWith(
            rules: e.rules.copyWith(multiMarkPolicy: MultiMarkPolicy.wrong),
          ),
          'Çift işaretli sorular yanlış sayılacak.',
        );
      }
    }

    // --- Yuvarlama ---
    if (s.contains('yuvarla')) {
      final step = s.contains('yarim')
          ? 0.5
          : RegExp(r'(yapma|olmasin|istemiyorum|yuvarlama$)').hasMatch(s)
          ? 0.0
          : s.contains('tam')
          ? 1.0
          : null;
      if (step != null) {
        return (
          e.copyWith(rules: e.rules.copyWith(roundingStep: step)),
          step == 0
              ? 'Puanlar yuvarlanmayacak.'
              : step == 0.5
              ? 'Puanlar yarım puana yuvarlanacak.'
              : 'Puanlar tam sayıya yuvarlanacak.',
        );
      }
    }

    final n = _questionNumber(s);
    final validN = n != null && n >= 1 && n <= e.choiceCount;

    // --- İptal kaldırma ---
    if (validN &&
        RegExp(r'iptal\w* (kaldir|geri al|kalksin|vazgec)|geri al')
            .hasMatch(s)) {
      return (_setCancelled(e, n, false), '$n. sorunun iptali kaldırıldı.');
    }

    // --- İptal ---
    final policy = s.contains('herkese') || s.contains('dogru say')
        ? CancelPolicy.countAsCorrect
        : RegExp(r'hesap\w* (cikar|disi)|dagit|yok say').hasMatch(s)
        ? CancelPolicy.exclude
        : null;
    if (validN && s.contains('iptal')) {
      var out = _setCancelled(e, n, true);
      if (policy != null) {
        out = out.copyWith(rules: out.rules.copyWith(cancelPolicy: policy));
      }
      return (
        out,
        '$n. soru iptal edildi: '
            '${out.rules.cancelPolicy.label.toLowerCase()}.',
      );
    }
    // "herkese doğru say" tek başına: iptal kuralını değiştirir.
    if (policy != null && n == null) {
      return (
        e.copyWith(rules: e.rules.copyWith(cancelPolicy: policy)),
        'İptal edilen sorular: ${policy.label.toLowerCase()}.',
      );
    }

    // --- Cevap anahtarı: "3. sorunun cevabı C", "3. soru C" ---
    if (validN) {
      final m = RegExp(
        r'(?:cevab\w*|yanit\w*|dogru\w*|soru\w*)\s+(?:sikki\s+)?([a-e](?:\+[a-e])*)(?:\s+sikki)?\s*(?:olsun|olacak|yap|dir|$)',
      ).firstMatch(s);
      if (m != null) {
        final opts = {
          for (final l in m.group(1)!.split('+')) 'abcde'.indexOf(l),
        };
        if (opts.every((o) => o < e.optionCount)) {
          final letters = (opts.toList()..sort())
              .map((o) => optionLetters[o])
              .join(' ve ');
          return (
            e.copyWith(
              choiceQuestions: [
                for (final q in e.choiceQuestions)
                  q.number == n ? q.copyWith(correctOptions: opts) : q,
              ],
            ),
            opts.length > 1
                ? '$n. sorunun doğru cevapları $letters yapıldı.'
                : '$n. sorunun cevabı $letters yapıldı.',
          );
        }
      }
    }
    return null;
  }

  Exam _setCancelled(Exam e, int n, bool v) => e.copyWith(
    choiceQuestions: [
      for (final q in e.choiceQuestions)
        q.number == n ? q.copyWith(cancelled: v) : q,
    ],
  );

  /// "5. soru", "beşinci soru", "on ikinci sorunun", "soru 7".
  int? _questionNumber(String s) {
    final digit = RegExp(r'(\d+)\s*\.?\s*(?:inci|nci|uncu|ncu|ıncı)?\s*soru')
        .firstMatch(s);
    if (digit != null) return int.parse(digit.group(1)!);
    final after = RegExp(r'soru\w*\s+(\d+)').firstMatch(s);
    if (after != null) return int.parse(after.group(1)!);
    final numbered = RegExp(r'(\d+) numara\w*\s+soru').firstMatch(s);
    if (numbered != null) return int.parse(numbered.group(1)!);
    final words = RegExp(r'((?:\w+\s+)?\w+)(?:\s+numara\w*)?\s+soru')
        .firstMatch(s);
    if (words != null) return _wordNumber(words.group(1)!);
    return null;
  }

  static const _units = {
    'bir': 1,
    'iki': 2,
    'uc': 3,
    'dort': 4,
    'bes': 5,
    'alti': 6,
    'yedi': 7,
    'sekiz': 8,
    'dokuz': 9,
  };
  static const _unitOrd = {
    'birinci': 1,
    'ilk': 1,
    'ikinci': 2,
    'ucuncu': 3,
    'dorduncu': 4,
    'besinci': 5,
    'altinci': 6,
    'yedinci': 7,
    'sekizinci': 8,
    'dokuzuncu': 9,
  };
  static const _tens = {
    'on': 10,
    'yirmi': 20,
    'otuz': 30,
    'kirk': 40,
    'elli': 50,
    'altmis': 60,
    'yetmis': 70,
    'seksen': 80,
    'doksan': 90,
  };
  static const _tensOrd = {
    'onuncu': 10,
    'yirminci': 20,
    'otuzuncu': 30,
    'kirkinci': 40,
    'ellinci': 50,
    'altmisinci': 60,
    'yetmisinci': 70,
    'sekseninci': 80,
    'doksaninci': 90,
  };

  int? _wordNumber(String phrase) {
    final w = phrase
        .split(RegExp(r'\s+'))
        .where((x) => !x.startsWith('numara'))
        .toList();
    if (w.isEmpty) return null;
    final last = w.last;
    final prev = w.length > 1 ? w[w.length - 2] : null;
    final lastVal = _unitOrd[last] ?? _units[last];
    if (lastVal != null) {
      return lastVal + (prev != null ? (_tens[prev] ?? 0) : 0);
    }
    return _tensOrd[last] ?? _tens[last];
  }

  /// Küçük harf, Türkçe karakterler sadeleşmiş, fazla boşluk atılmış.
  static String normalize(String text) {
    const from = 'çğıİöşüÇĞIÖŞÜâÂîÎûÛ';
    const to = 'cgiiosucgiosuaaiiuu';
    final b = StringBuffer();
    for (final ch in text.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[!?"“”]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
