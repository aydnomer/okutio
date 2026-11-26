// Açık uçlu cevap için yapay zekâ puan önerisi.
//
// Uygulama, öğrencinin cevap alanının düzeltilmiş fotoğrafını (yalnızca cevap
// alanı: ad, numara, QR gönderilmez), soruyu, beklenen cevabı ve ölçütleri
// gönderir. Claude el yazısını okur, her ölçüt için öneri verir. Puan hiçbir
// zaman kendiliğinden kesinleşmez; öğretmen onaylar.
//
// Gizli anahtar: `supabase secrets set ANTHROPIC_API_KEY=...`
// Yayın:        `supabase functions deploy grade-open-answer`
import Anthropic from "npm:@anthropic-ai/sdk";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk/helpers/zod";
import { z } from "npm:zod";

const client = new Anthropic(); // ANTHROPIC_API_KEY ortam değişkeninden

const Criterion = z.object({
  title: z.string(),
  weightPercent: z.number(),
});

const RequestBody = z.object({
  imageBase64: z.string().min(100).max(8_000_000),
  mediaType: z.enum(["image/jpeg", "image/png"]).default("image/jpeg"),
  questionNumber: z.number().int(),
  maxPoints: z.number().positive().max(1000),
  prompt: z.string().max(4000).default(""),
  referenceAnswer: z.string().max(4000).default(""),
  rubric: z.array(Criterion).max(20).default([]),
  subject: z.string().max(200).default(""),
});

const Grading = z.object({
  transcription: z.string(),
  legible: z.boolean(),
  criteria: z.array(
    z.object({
      title: z.string(),
      earnedFraction: z.number(),
      reason: z.string(),
    }),
  ),
  confidence: z.enum(["high", "medium", "low"]),
  feedback: z.string(),
});

const SYSTEM = `Sen Türkiye'de bir öğretmenin yazılı sınav kâğıtlarını puanlamasına yardım eden bir asistansın.
Sana öğrencinin el yazısıyla yazdığı cevabın fotoğrafı, soru, öğretmenin beklediği cevap ve puanlama ölçütleri verilir.

Yapacakların:
1. transcription: Öğrencinin yazdığını olduğu gibi, düzeltmeden yaz. Okuyamadığın kelimeyi [okunamadı] olarak yaz. Çizilmiş (karalanmış) kısımları alma.
2. criteria: Her ölçüt için earnedFraction değerini 0 ile 1 arasında ver (0, 0.25, 0.5, 0.75, 1 gibi). reason alanında öğretmene tek cümlelik Türkçe gerekçe yaz. Ölçütlerin başlıklarını aynen kullan.
3. legible: Cevabın büyük kısmı okunabiliyorsa true.
4. confidence: Okuma ve değerlendirmeden ne kadar eminsin. Yazı kötüyse, cevap belirsizse ya da beklenen cevapla karşılaştırmak yoruma açıksa medium ya da low ver.
5. feedback: Öğrenciye verilebilecek, kısa, nazik ve yol gösteren bir Türkçe geri bildirim (en fazla iki cümle).

Kurallar:
- Yazım ve dil bilgisi hatalarını, ölçütlerde açıkça istenmedikçe puan kırma sebebi sayma.
- Beklenen cevapla aynı anlama gelen farklı ifadeleri doğru kabul et.
- Emin olmadığında puanı yüksek tahmin etme; confidence değerini düşür. Son kararı öğretmen verir.
- Boş ya da tamamen ilgisiz cevaplarda tüm ölçütler 0'dır.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Yalnızca POST" }, 405);

  const parsed = RequestBody.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return json({ error: "Geçersiz istek", details: parsed.error.issues }, 400);
  }
  const b = parsed.data;
  const rubric = b.rubric.length > 0
    ? b.rubric
    : [{ title: "Cevabın doğruluğu ve tamlığı", weightPercent: 100 }];

  const task = [
    b.subject ? `Ders: ${b.subject}` : null,
    `Soru ${b.questionNumber} (${b.maxPoints} puan)${b.prompt ? `: ${b.prompt}` : ""}`,
    b.referenceAnswer ? `Öğretmenin beklediği cevap: ${b.referenceAnswer}` : "Beklenen cevap verilmedi; konu bilgine göre değerlendir.",
    "Puanlama ölçütleri:",
    ...rubric.map((c) => `- ${c.title} (%${c.weightPercent})`),
  ].filter(Boolean).join("\n");

  try {
    const response = await client.beta.messages.create({
      model: "claude-opus-5-5",
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "high", format: zodOutputFormat(Grading) },
      system: SYSTEM,
      messages: [{
        role: "user",
        content: [
          {
            type: "image",
            source: { type: "base64", media_type: b.mediaType, data: b.imageBase64 },
          },
          { type: "text", text: task },
        ],
      }],
    });

    if (response.stop_reason === "refusal") {
      return json({ error: "Bu cevap için öneri üretilemedi. Elle puanlayın." }, 422);
    }
    const text = response.content
      .flatMap((block) => (block.type === "text" ? [block.text] : []))
      .join("");
    const grading = Grading.safeParse(JSON.parse(text));
    if (!grading.success) {
      return json({ error: "Yanıt okunamadı. Elle puanlayın." }, 502);
    }

    // Puanı sunucuda, ölçüt ağırlıklarıyla hesapla (modelin aritmetiğine güvenme).
    const g = grading.data;
    let fraction = 0;
    const criteria = rubric.map((c) => {
      const found = g.criteria.find((x) => x.title === c.title);
      const f = Math.min(1, Math.max(0, found?.earnedFraction ?? 0));
      fraction += (f * c.weightPercent) / 100;
      return {
        title: c.title,
        weightPercent: c.weightPercent,
        earnedFraction: f,
        points: (b.maxPoints * c.weightPercent * f) / 100,
        reason: found?.reason ?? "",
      };
    });
    // Yarım puana yuvarla; öğretmen dilediği gibi değiştirir.
    const suggested = Math.round(b.maxPoints * Math.min(1, fraction) * 2) / 2;

    return json({
      transcription: g.transcription,
      legible: g.legible,
      confidence: g.confidence,
      feedback: g.feedback,
      criteria,
      suggestedScore: suggested,
      model: response.model,
    });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "Şu an çok yoğun. Biraz sonra tekrar deneyin." }, 429);
    }
    if (error instanceof Anthropic.APIError) {
      return json({ error: `Yapay zekâ hizmeti hatası (${error.status}).` }, 502);
    }
    return json({ error: "Beklenmeyen hata." }, 500);
  }
});
