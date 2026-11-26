import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okutio/core/ai/ai_grader.dart';
import 'package:okutio/core/models/question.dart';

void main() {
  const q = OpenQuestion(
    number: 1,
    maxPoints: 20,
    prompt: 'Fotosentezi açıklayınız.',
    rubric: [RubricCriterion(title: 'Tanım', weightPercent: 100)],
  );

  test('öneri okunur, istek öğrenci bilgisi içermez', () async {
    late Map<String, Object?> sent;
    final client = MockClient((req) async {
      sent = (jsonDecode(req.body) as Map).cast<String, Object?>();
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'transcription': 'Bitkiler güneş ışığıyla besin üretir.',
            'suggestedScore': 15,
            'confidence': 'medium',
            'feedback': 'Klorofili de anmalısın.',
            'legible': true,
            'criteria': [
              {'title': 'Tanım', 'points': 15, 'reason': 'Eksik ama doğru.'},
            ],
          }),
        ),
        200,
      );
    });
    final s = await AiGrader(
      client: client,
      url: 'https://x.test/f',
    ).grade(jpeg: Uint8List.fromList(List.filled(200, 1)), question: q);
    expect(s.suggestedScore, 15);
    expect(s.confidenceLabel, 'Kısmen emin');
    expect(s.criteria.single.reason, 'Eksik ama doğru.');
    expect(sent.keys, isNot(contains('studentNumber')));
    expect(sent.keys, isNot(contains('studentName')));
    expect(sent['maxPoints'], 20);
  });

  test('sunucu hatası anlaşılır mesajla döner', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode({'error': 'Şu an çok yoğun.'})),
        429,
      ),
    );
    expect(
      () => AiGrader(
        client: client,
        url: 'https://x.test/f',
      ).grade(jpeg: Uint8List(10), question: q),
      throwsA(
        isA<AiGraderException>().having(
          (e) => e.message,
          'm',
          'Şu an çok yoğun.',
        ),
      ),
    );
  });

  test('adres verilmemişse kapalı', () {
    expect(
      () => AiGrader(url: '').grade(jpeg: Uint8List(1), question: q),
      throwsA(isA<AiGraderException>()),
    );
  });
}
