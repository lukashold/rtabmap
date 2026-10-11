# KANTURA'ya katkıda bulunma

KANTURA, RTAB-Map'in bağımsız bir çatallamasıdır. Geliştirme ve çekme istekleri [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main) dalını hedefler. [İngilizce ana kılavuz](../../CONTRIBUTING.md) sürecin tamamını açıklar.

## Başlangıç ve geliştirme

[Çalışma alanı kılavuzunu](../../tools/scan-workspace/README.md), [özellik karşılaştırmasını](../KANTURA-FEATURES.md) ve [doğrulama kayıtlarını](../../tools/scan-workspace/VALIDATION.md) okuyun. Önce [projenin sorun kayıtlarında](https://github.com/lukashold/rtabmap/issues) arama yapın. Yeniden üretilebilir bir hata, odaklı bir iyileştirme, çeviri veya gerçek cihaz testi yararlı bir başlangıçtır.

Tarayıcı sürümü için tam depoyu, Node.js 24'ü ve pnpm 11.25.0'ı kullanın. `kantura/main` üzerinden bir dal oluşturun. `tools/scan-workspace` içinde şunları çalıştırın:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

`http://localhost:4173` adresini açın. Ana kılavuz Corepack, Docker ve sunucu depolamasını açıklar. Geometri ve veri kalıcılığı değişikliklerini test edin. Metin düzeltmelerinde ilgili dili ve yerleşimi kontrol edin. Gerçekte yaptığınız ve henüz yapamadığınız kontrolleri belirtin.

## Çeviri ve açıklamalar

Türkçe dil paketi `tools/scan-workspace/locales/tr.json` dosyasındadır. Anahtarları, sahne ve simge kimliklerini, birimleri ve yer tutucuları koruyun. Altyazıları anlatımla uyumlu tutun. Yerel kılavuz ve arayüzle bütünleşmesini de kontrol edin; kılavuz çevirisi, tüm yerel ekranların çevrildiğini kanıtlamaz. Metin kesiliyorsa ekran görüntüsü ekleyin.

Videolar sentetik animasyonlardır; gerçek taramalar değildir. Bu açıklamayı, RoomPlan ile LiDAR arasındaki farkı, ölçüm ve taşıma tahmini sınırlamalarını koruyun. Her odanın ayrı bir başlangıç noktası vardır; odalar otomatik olarak hizalanmaz.

## Cihazda test

iOS için Mac, uyumlu Xcode, yerel bağımlılıklar ve kendi imzanız gerekir. [Kurulum kılavuzuna](../APP-STORE-RELEASE.md) bakın. `app/ios/Tests/run-scan-tracking-tests.sh` ve `run-measurement-guide-tests.sh` içindeki Swift testleri, iPhone'da taramanın yerini tutmaz.

Revizyonu, cihazı, iOS sürümünü, modu, adımları ve beklenen/gözlenen sonuçları belirtin. Ölçümleri şerit metreyle karşılaştırıp değerleri ve birimleri yazın. Sentetik verileri işaretleyin. Değişikliğe göre oda, bahçe kapısı, kesinti, kaydetme/yeniden açma, fotoğraf ve dışa aktarmayı test edin. Yalnızca paylaşmaya yetkili olduğunuz örnekleri kullanın; özel iç mekânları, kişileri veya kimlik bilgilerini izinsiz ifşa etmeyin.

## Değişiklik önerme ve lisanslar

Depoyu çatallayın, `kantura/main` üzerinden bir dal oluşturun, odaklı değişikliği yapıp test edin ve **`lukashold/rtabmap:kantura/main`** dalına bir çekme isteği açın. Sorunu, nihai sonucu ve sınırlamaları açıklayın. Genel RTAB-Map düzeltmeleri özgün projeye ayrıca önerilebilir; KANTURA'ya özgü özellikler öncelikle bu çatallamaya yöneliktir.

Proje kodu [BSD 3-Clause](../../LICENSE) lisansını kullanır. Atıfları koruyun ve yalnızca dağıtma hakkınız olan içerikle katkıda bulunun. Yerel bağımlılıkların ayrı koşulları vardır: `WITH_ORB_OCTREE` ile etkinleştirilen ORB-Octree GPLv3'tür; OpenCV Nonfree'yi etkinleştirir; SuiteSparse/g2o bileşenleri ile statik bağlanan LASzip 2.0.1/libLAS hâlâ incelenmelidir. Yeni bağımlılıkların sürümünü ve lisansını belgeleyin. [Yayın denetimi](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen), tamamlanmış bir App Store onayı değildir.
