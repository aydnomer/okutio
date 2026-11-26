/// Kitapçık türü (A, B, C, D) ve ana kitapçığa göre karıştırma haritası.
library;

class Booklet {
  const Booklet({
    required this.code,
    required this.questionOrder,
    this.optionMaps = const {},
  });

  /// Ana kitapçık: sorular ve şıklar karıştırılmamış.
  factory Booklet.master(int questionCount, {String code = 'A'}) => Booklet(
    code: code,
    questionOrder: [for (var i = 1; i <= questionCount; i++) i],
  );

  /// Kitapçık kodu: 'A', 'B', ...
  final String code;

  /// `questionOrder[i]`, bu kitapçığın (i+1). sorusunun ana kitapçıktaki numarasıdır.
  final List<int> questionOrder;

  /// Şıkları karıştırılmış sorular için: ana soru numarası →
  /// `liste[kitapçıkŞıkkı] = anaKitapçıkŞıkkı`. Listede olmayan soruların şıkları aynıdır.
  final Map<int, List<int>> optionMaps;

  int get questionCount => questionOrder.length;

  bool get isIdentity {
    for (var i = 0; i < questionOrder.length; i++) {
      if (questionOrder[i] != i + 1) return false;
    }
    return optionMaps.isEmpty;
  }

  /// Bu kitapçıktaki soru numarasını ana kitapçık numarasına çevirir.
  int masterNumberOf(int bookletNumber) => questionOrder[bookletNumber - 1];

  /// Bu kitapçıkta işaretlenen şıkkı ana kitapçıktaki şıkka çevirir.
  int masterOptionOf(int masterNumber, int bookletOption) {
    final map = optionMaps[masterNumber];
    return map == null ? bookletOption : map[bookletOption];
  }

  /// Ana kitapçıktaki şıkkın bu kitapçıktaki karşılığı.
  int bookletOptionOf(int masterNumber, int masterOption) {
    final map = optionMaps[masterNumber];
    return map == null ? masterOption : map.indexOf(masterOption);
  }

  /// Ana kitapçık numarasının bu kitapçıktaki karşılığı.
  int bookletNumberOf(int masterNumber) =>
      questionOrder.indexOf(masterNumber) + 1;

  /// Haritanın tutarlı olup olmadığını denetler. Sorun yoksa boş liste döner.
  List<String> validate({required int optionCount}) {
    final problems = <String>[];
    final sorted = [...questionOrder]..sort();
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i] != i + 1) {
        problems.add('$code kitapçığında soru sırası eksik ya da tekrarlı.');
        break;
      }
    }
    optionMaps.forEach((master, map) {
      final s = [...map]..sort();
      final ok =
          s.length == optionCount &&
          List.generate(optionCount, (i) => i).every((i) => s[i] == i);
      if (!ok) {
        problems.add(
          '$code kitapçığı, ana kitapçığın $master. sorusunun şık eşleşmesi hatalı.',
        );
      }
    });
    return problems;
  }

  Map<String, Object?> toJson() => {
    'code': code,
    'questionOrder': questionOrder,
    'optionMaps': {for (final e in optionMaps.entries) '${e.key}': e.value},
  };

  factory Booklet.fromJson(Map<String, Object?> json) => Booklet(
    code: json['code'] as String,
    questionOrder: (json['questionOrder'] as List<Object?>).cast<int>(),
    optionMaps: {
      for (final e
          in ((json['optionMaps'] as Map?) ?? const {})
              .cast<String, Object?>()
              .entries)
        int.parse(e.key): (e.value! as List<Object?>).cast<int>(),
    },
  );
}
