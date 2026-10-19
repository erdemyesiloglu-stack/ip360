# IP360 · Akış IPTV

Android ve Windows tarayıcılarında çalışan kişisel IPTV oynatıcı.
Uygulama yayın veya abonelik içermez; kendi M3U ya da Xtream kaynağınızı eklersiniz.

## Cloudflare Pages ile yayınlama

Cloudflare hesabınızda **Workers & Pages → Create application → Pages → Connect to Git**
yolunu kullanın. Arayüzdeki adlar değişebilir; GitHub deposundan bir **Pages**
projesi oluşturmayı seçin. Depo: `erdemyesiloglu-stack/ip360`.

| Ayar | Değer |
| --- | --- |
| Production branch | `main` |
| Framework preset | `None` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Root directory | Varsayılan / boş |

**Save and Deploy** ile ilk yayını başlatın. Cloudflare'ın verdiği `pages.dev`
adresi uygulamanın sabit adresidir. `main` dalına sonraki güncellemeler
gönderildiğinde Cloudflare otomatik yayınlar; kullanıcılar tekrar dosya indirmez.
Alan adı daha sonra Pages projesindeki Custom domains alanından bağlanabilir.

Bu depoya erişim verilmesi Cloudflare hesabınıza erişim vermez. GitHub bağlantısı
ve ilk Pages projesinin oluşturulması hesabınızda bir defa tamamlanmalıdır.

## Özellikler

- M3U bağlantısı ve UTF-8 `.m3u` / `.m3u8` dosyası (en fazla 20 MB)
- Xtream Codes giriş doğrulaması, canlı kanallar ve sağlayıcı kategorileri
- Açılıp kapanan Kanallar, Filmler ve Diziler menüsü
- Ulusal, Spor, Haber, Belgesel ve diğer kategori filtreleri
- Filmler / diziler için tür filtreleri; M3U içeriği üzerinden sınıflandırma
- Tam sayfa logo / afiş kataloğu; karta tıklayınca oynatıcıya geçiş
- Kaynak görselleri, eksik görsel için yer tutucu, arama ve favoriler
- HLS, tarayıcı destekli MP4/WebM, ses ve tam ekran kontrolleri
- Kaynağı cihazda hatırlama; destekleyen tarayıcılarda PWA kurulumu

**Kapsam:** Xtream entegrasyonu şu anda canlı kanalları yükler. Xtream film/dizi
katalog ve sezon API'leri henüz eklenmedi. M3U film/dizi kayıtları desteklenir.
Türler kaynak grupları ve adres ipuçlarından çıkarılır. Kanal/afiş görselleri
sağlayıcıdan gelir; uygulama görsel veritabanı veya içerik sağlamaz.

## Uyumluluk ve gizlilik

HTTPS sayfada HTTPS yayın adresi gerekir. Sağlayıcının API, listeler, HLS manifestleri
ve yayın parçalarında CORS erişimine izin vermesi gerekir. DRM, özel istek başlıkları,
ham TS ve bazı ses/video kodekleri desteklenmeyebilir. Aracı sunucu veya yayın
dönüştürme yoktur; bağlantılar doğrudan cihazınızdan sağlayıcıya gider.

“Kaynağı bu cihazda hatırla” açıksa son kaynak IndexedDB'de AES-GCM ile şifreli
saklanır. Anahtar da aynı tarayıcıdadır; bu, aynı tarayıcıya erişen kişilere karşı
erişim kilidi değildir. Kaydı Kaynağı sil düğmesiyle veya Gizlilik penceresinden
kaldırabilirsiniz. Favoriler adreslerin SHA-256 özetleri olarak saklanır. Tarayıcı
verilerini silmek kayıtları kaldırır. Kayıtlar cihazlar arasında eşitlenmez.
Önceden indirdiğiniz HTML dosyasındaki kayıtlar yeni web adresine otomatik taşınmaz;
web sitesinde kaynağı bir kez yeniden ekleyin.

Service worker yalnızca uygulama dosyalarını önbelleğe alır. Yayınlar internet
gerektirir. HLS.js gerektiğinde jsDelivr'dan yüklenir; CDN erişimi gerekir.
Sağlayıcı IP adresinizi ve hesap/yayın isteklerini görebilir. Uygulama bunları
bir uygulama sunucusunda saklamaz ve kullanımın gizliliğini garanti etmez.

## Geliştirme ve doğrulama

Node.js 20 veya üstü ile `npm run build`, kaynak testlerini ve statik yayın
dosyalarını kontrol eder. Harici npm bağımlılığı veya frontend derleyicisi yoktur;
`dist` klasörü doğrudan yayınlanır.

Yerel önizleme için Python 3 kuruluysa `npm start` ve `http://localhost:4173`.
`npm run standalone` kurulum gerektirmeyen `akis-iptv.html` dosyasını üretir.

19 parser, kategori, ağ okuma ve şifreleme testi geçti. Gerçek sağlayıcı hesabı
ile oynatma ve gerçek Android/Windows tarayıcı testleri ayrıca yapılmalıdır.
Bu depoya yüklenmiş olması, Pages projesinin henüz yayınlandığı anlamına gelmez.
