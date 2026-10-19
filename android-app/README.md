# IP360 Android

Flutter ile telefon, tablet ve Android TV için doğrudan IPTV oynatıcı.
Android platform iskeleti sabitlenmiş Flutter SDK ile hazırlama betiği tarafından
oluşturulur. Paket kimliği: `com.erdemyesiloglu.ip360`.

## Özellikler

- HTTP / HTTPS M3U bağlantısı ve M3U dosyası (100 MB sınır, satır satır okuma)
- Xtream canlı kanallar, filmler, diziler ve sezon/bölüm seçimi
- Açılır kategoriler, tam sayfa logo/afiş kataloğu, arama ve favoriler
- Doğrudan video oynatma; aracı sunucu veya tarayıcı WebView kullanılmaz
- Android güvenli deposunda M3U/Xtream kaynağı ve favori kaydı
- Telefon/tablet arayüzü, TV başlatıcı kaydı ve kumanda odak vurgusu

Android uygulamasında tarayıcı CORS kısıtı yoktur. HTTP kaynaklar için manifest
izni vardır; HTTP ağ trafiği şifrelenmez. HTTPS sertifika doğrulaması kapatılmaz.
Sağlayıcı, hesabın durumuna veya bağlantı adresine göre erişimi yine reddedebilir.
DRM veya tüm kodeklerin çalışması garanti edilmez. Uygulama yayın/abonelik içermez.

Kaynak bilgileri yalnızca Android cihazında tutulur. Kilidi açık cihazı kullanan
kişiler yayını açabilir. M3U dosyaları şu anda yalnızca oturumda yüklenir; kalıcı
kaynak için M3U bağlantısı veya Xtream hesabı ekleyin. Android otomatik yedekleme
devre dışıdır. Kaynağı sil düğmesi kaydı kaldırır.

## APK üretimi

GitHub Actions → **Android APK** iş akışı `android-app` dalındaki değişikliklerde
çalışır; analiz, test ve APK derlemesi yapar. Başarılı çalışmanın **Artifacts**
bölümündeki `IP360-Android-APK` paketini indirin. Modern telefon/tablet/TV için
`app-arm64-v8a-release.apk`, eski 32-bit cihaz için `app-armeabi-v7a-release.apk`,
emülatör için `app-x86_64-release.apk` kullanılır.

Bu APK'lar Flutter'ın varsayılan geliştirme imzasını kullanır. Mağaza yayını ve
kalıcı güncellemeler için kullanıcıya ait sabit release imzası ayrıca gerekir.
İlk hedef cihazlarda kurulabilen deneme APK'sıdır; Play Store'a gönderilmez.

Yerelde Flutter 3.35.7, Android SDK ve JDK 17 ile:

```sh
bash tool/prepare_android.sh /tmp/ip360-build
cd /tmp/ip360-build
dart format lib test tool
flutter analyze --fatal-infos
flutter test
flutter build apk --release --split-per-abi
```

Gerçek sağlayıcı hesabı, fiziksel telefon/tablet ve TV üzerinde oynatma, kumanda
ile tüm oynatıcı kontrolleri ve kaynak kaydının uygulama yeniden açılınca
korunması ayrıca doğrulanmalıdır.

## 0.2.0 arayüz ve rehber

- Canlı TV: Logolar / Liste / Rehber; geniş ekranlarda yan yana kanal ve video önizlemesi.
- Telefonlarda önizleme üstte, kaydırılabilir kanal listesi altta.
- Canlı yayından geri dönüldüğünde önizleme sürer; kategori değişince durur.
- XMLTV bağlantısı Ayarlar > Yayın rehberi bölümünden eklenir; Xtream adresi hesap bilgilerinden önerilir.
- M3U tvg-id ve Xtream epg_channel_id ile birebir eşleştirme; 90 dakikalık zaman çizelgesi, şimdi/sıradaki program, program açıklaması.
- XMLTV saat dilimleri işlenir; rehber çözümlemesi arka planda yapılır. XMLTV dosyası en fazla 30 MB; sıkıştırılmış XMLTV ayrıca desteklenmez.
- Hatırlanan rehber URL'si güvenli depoda ilgili kaynakla eşleştirilir. Program verisi oturumda tutulur, açılışta tekrar indirilir.
- Film/dizi detay penceresi ve sağlayıcının döndürdüğü açıklama; dizi bölümleri mevcut seçicide açılır.
- Kayıt, catch-up, çoklu kaynak, çoklu ekran ve Stalker Portal bu sürümde uygulanmadı.
