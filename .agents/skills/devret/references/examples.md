# İhtiyaca göre görev örnekleri

Bu örnekler izin vermez; mevcut kullanıcı talebi ve proje planına göre doldurulur. Tüm işçiler yeni/asgari bağlamla açılır ve alt ajan oluşturamaz.

## Yeni UI / yeniden tasarım

Önce `devret-designer`, `gpt-6.1-sol`, `medium`:

```text
Hedef: Planın sipariş ekranı maddesine uygun tasarım kararları çıkar.
Hedef kitle: Depo operasyon çalışanları.
Kullanım: Yoğun vardiyada geciken siparişi bulmak ve ayrıntıya ulaşmak.
Tasarım sistemi: src/ui/* bileşenleri ve DESIGN.md; mevcut header korunacak.
Kısıtlar: Türkçe, masaüstü ve 390px dar ekran, yeni paket yok.
Dosyalar: Planın ilgili maddesi, DESIGN.md, src/pages/Orders.tsx; salt oku.
Kabul: Hiyerarşi, filtre davranışı, yükleniyor/boş/hata durumları ve dar ekran kararları somut.
Önemli bilgi eksikse sor. Dönüş: kararlar, ilgili dosyalar, kanıt, sorular.
```

Tasarım yanıtını aldıktan sonra `devret-implementer` Sol / medium'a yalnızca kabul edilen kararları, izinli dosyaları ve kontrol komutlarını aktar. Uygulama kapsamlıysa veya ilk sonuçta belirgin sorun varsa `devret-critic` Sol / medium ile incele. Düzeltmeleri ilk uygulayıcıya gönder. Tarayıcıda gerçekten masaüstü ve dar ekranı gözle; mümkün olmadıysa açıkça kalan kontrol olarak yaz.

## Uygulama ve aynı işçide düzeltme

`devret-implementer`, `gpt-6.1-sol`, `medium`:

```text
Hedef: Planın arama maddesi kapsamında boş sorguda gereksiz istek atılmasını düzelt.
Bağlam: Kullanıcı filtreyi temizlediğinde sonuç listesi mevcut yerel veriyle kalmalı.
Dosyalar: src/search.ts ve mevcut tests/search.test.ts. Bu dosyaların tek yazıcısısın.
İzin: Kök nedeni araştır, bu davranışı düzelt, mevcut test kapsamına anlamlı kontrol ekle.
Yasak: API sözleşmesi değiştirme, paket ekleme, ilgisiz refactor, commit/push, delegasyon.
Kabul: Boş sorgu ağ isteği üretmez; dolu sorgu mevcut davranışını korur.
Kontrol: package.json içindeki mevcut arama testi komutunu çalıştır; komut ve sonucu raporla.
Dönüş: Kısa özet, dosyalar, kanıt, sorular.
```

Kontrol başarısızsa yeni ajan açmadan aynı işçiye başarısız komutu ve gerekli kısa logu gönder. Başka dosyaya ihtiyaç varsa sahipliği ve kapsamı önce yönetici çözer.

## Tam Luna sözleşmesi

`devret-helper`, `gpt-6-luna`, `low`:

```text
Hedef: docs/usage.md içindeki kaldırılmış komut adının iki örneğini güncelle.
Bağlam: Planın belge maddesi; gerçek CLI artık `widget inspect` kullanıyor.
Dosyalar: docs/usage.md (yaz); src/cli.ts (yalnızca kontrol için oku).
Adımlar: CLI adını doğrula; belirtilen iki kod örneğinde `widget show` yerine `widget inspect` yaz; diff'i kontrol et.
İzinli düzenlemeler: Yalnızca docs/usage.md içindeki bu iki komut örneği.
Yasaklar: Başka metin/dosya, biçim toplu değişikliği, paket, commit/push, delegasyon.
Çıktı örneği: "İki örnek güncellendi. Dosya: docs/usage.md. Kontrol: git diff --check geçti. Sorular: yok."
Kontroller: git diff --check; git diff -- docs/usage.md; CLI adıyla karşılaştır.
Kabul: Tam iki örnek doğru komutu gösterir; başka içerik değişmez; diff temizdir.
Dur: CLI beklenen adı doğrulamıyorsa, eşleşme sayısı iki değilse veya başka düzenleme gerekiyorsa değişiklik yapmadan sor.
```

Bu bilgi kullanıcı talebinde yoksa Luna'ya tahmin ettirme. Yönetici ilgili dosyaları araştırıp sözleşmeyi tamamlar veya belirsiz işi Sol'a verir.
