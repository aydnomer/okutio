/// Açık uçlu cevaplar için yapay zekâ puan önerisi.
///
/// Fotoğraf sunucudaki bir fonksiyona gider (anahtar uygulamada durmaz);
/// yalnızca cevap alanı gönderilir, öğrencinin adı ve numarası gönderilmez.
/// Dönen puan bir öneridir, öğretmen onaylamadan kesinleşmez.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/question.dart';

/// Derlerken verilir: --dart-define=AI_GRADER_URL=... --dart-define=AI_GRADER_KEY=...
const aiGraderUrl = String.fromEnvironment('AI_GRADER_URL');
const aiGraderKey = String.fromEnvironment('AI_GRADER_KEY');

bool get aiGraderConfigured => aiGraderUrl.isNotEmpty;

class AiCriterionResult {
  const AiCriterionResult({
    required this.title,
    required this.points,
    required this.reason,
  });

  final String title;
  final double points;
  final String reason;
}

class AiSuggestion {
  const AiSuggestion({
    required this.transcription,
    required this.suggestedScore,
    required this.confidence,
    required this.feedback,
    required this.legible,
    required this.criteria,
  });

  factory AiSuggestion.fromJson(Map<String, Object?> j) => AiSuggestion(
    transcription: j['transcription'] as String? ?? '',
    suggestedScore: (j['suggestedScore'] as num? ?? 0).toDouble(),
    confidence: j['confidence'] as String? ?? 'low',
    feedback: j['feedback'] as String? ?? '',
    legible: j['legible'] as bool? ?? false,
    criteria: [
      for (final c in (j['criteria'] as List<Object?>? ?? const []))
        if (c is Map)
          AiCriterionResult(
            title: c['title'] as String? ?? '',
            points: (c['points'] as num? ?? 0).toDouble(),
            reason: c['reason'] as String? ?? '',
          ),
    ],
  );

  /// Öğrencinin yazdığının okunmuş hâli.
  final String transcription;
  final double suggestedScore;

  /// high / medium / low
  final String confidence;
  final String feedback;
  final bool legible;
  final List<AiCriterionResult> criteria;

  String get confidenceLabel => switch (confidence) {
    'high' => 'Emin',
    'medium' => 'Kısmen emin',
    _ => 'Emin değil, kontrol edin',
  };
}

class AiGraderException implements Exception {
  const AiGraderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiGrader {
  AiGrader({http.Client? client, String? url, String? key})
    : _client = client ?? http.Client(),
      _url = url ?? aiGraderUrl,
      _key = key ?? aiGraderKey;

  final http.Client _client;
  final String _url;
  final String _key;

  Future<AiSuggestion> grade({
    required Uint8List jpeg,
    required OpenQuestion question,
    String subject = '',
  }) async {
    if (_url.isEmpty) {
      throw const AiGraderException('Yapay zekâ önerisi bu sürümde kapalı.');
    }
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_url),
            headers: {
              'Content-Type': 'application/json',
              if (_key.isNotEmpty) 'Authorization': 'Bearer $_key',
              if (_key.isNotEmpty) 'apikey': _key,
            },
            body: jsonEncode({
              'imageBase64': base64Encode(jpeg),
              'mediaType': 'image/jpeg',
              'questionNumber': question.number,
              'maxPoints': question.maxPoints,
              'prompt': question.prompt,
              'referenceAnswer': question.referenceAnswer,
              'rubric': [for (final c in question.rubric) c.toJson()],
              'subject': subject,
            }),
          )
          .timeout(const Duration(seconds: 90));
    } on Object {
      throw const AiGraderException(
        'Yapay zekâya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
      );
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200 || body is! Map) {
      final msg = body is Map ? body['error'] as String? : null;
      throw AiGraderException(msg ?? 'Öneri alınamadı (${res.statusCode}).');
    }
    return AiSuggestion.fromJson(body.cast<String, Object?>());
  }
}
