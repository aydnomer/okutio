# Okutio

> Çalışma adı. Ürün adı kesinleşince değiştirilecek.

Öğretmenlerin hem **çoktan seçmeli (optik)** hem **açık uçlu (el yazısı)** sınav kâğıtlarını
telefon kamerası ya da okulun tarayıcısıyla okutup puanlamasını sağlayan uygulama.
Tek Flutter kod tabanından **Android, iOS ve web** sürümü çıkar.

## Öne çıkanlar

- Adım adım sınav oluşturma sihirbazı (teknolojiyle arası iyi olmayan öğretmen için tasarlandı)
- A/B/C/D kitapçık desteği: öğretmen yalnızca A kitapçığının anahtarını girer
- Esnek puanlama kuralları: yanlış götürme (3/4), soru puanı, iptal edilen soru, çift işaretleme
- QR kodlu ve köşe işaretli, yazdırılabilir optik form (PDF)
- e-Okul'a uygun Excel çıktısı (yol haritasında)
- Açık uçlu sorularda öğretmen onaylı yapay zekâ puanlaması (yol haritasında)

## Durum

| Bölüm | Durum |
|---|---|
| Sınav oluşturma sihirbazı (7 adım) | Hazır |
| Cevap anahtarı (dokunarak / yazarak, iptal, çoklu doğru) | Hazır |
| Açık uçlu soru puanı ve puanlama ölçütleri | Hazır |
| Optik form PDF'i, yazdırma, indirme | Hazır |
| Puanlama motoru (kitapçık, yanlış götürme, iptal) | Hazır, testli |
| Kâğıt tarama (kamera / toplu PDF) | Sıradaki |
| Sonuçlar ve e-Okul Excel çıktısı | Planlandı |

## Geliştirme

```bash
flutter pub get
flutter test          # birim testleri
flutter analyze       # statik analiz
flutter run -d chrome # web'de çalıştır
```

Gereken Flutter sürümü: 3.50 veya üzeri (Dart 3.14).

Web derlemesi, yazı tiplerini ve CanvasKit'i internetten çekmesin diye şöyle alınır:

```bash
flutter build web --release --no-web-resources-cdn
```

## Sürekli entegrasyon ve web yayını

`.github/workflows/ci.yml` her gönderimde biçim, analiz, test ve web derlemesini çalıştırır.
`main` dalına gelen her değişiklik GitHub Pages'e yayınlanır. İlk seferde depo ayarlarında
**Settings → Pages → Source: GitHub Actions** seçilmelidir.

## Klasör yapısı

```
lib/
  app/        Uygulama kabuğu: tema, yönlendirme
  core/       Ekranlardan bağımsız iş mantığı: modeller, puanlama,
              optik form yerleşimi (form/form_layout.dart) ve PDF üretimi
  data/       Veri saklama (şimdilik cihazda, sonra Supabase)
  features/   Ekranlar, özellik bazında klasörlenmiş
test/         Birim ve widget testleri
```

## Tasarım ilkeleri

1. Öğretmen hiçbir zaman teknik bir kelimeyle karşılaşmaz.
2. Her ekranda tek bir ana iş vardır.
3. Hiçbir puan öğretmenin onayı olmadan kesinleşmez.
