import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'source.dart';
import 'epg.dart';
import 'ui/live_workspace.dart';

class _PlaybackIntent extends Intent { const _PlaybackIntent(); }

const mint = Color(0xFF79E9C2);
const kinds = {'live': 'Kanallar', 'movies': 'Filmler', 'series': 'Diziler'};
const kindIcons = {'live': Icons.live_tv, 'movies': Icons.movie_outlined, 'series': Icons.video_library_outlined};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const IptvApp());
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'IP360', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: mint, brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF11161E),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF11161E), surfaceTintColor: Colors.transparent),
      dividerColor: const Color(0xFF2A3441),
      listTileTheme: const ListTileThemeData(iconColor: Colors.white60, textColor: Colors.white, selectedColor: mint),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF1B2430),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
    home: const Home(),
  );
}

class _SourceInput {
  const _SourceInput({this.config, this.remember = true, this.file = false});
  final SourceConfig? config;
  final bool remember, file;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _client = http.Client();
  final _vault = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final _player = Player();
  late final _video = VideoController(_player);
  final _search = TextEditingController();
  StreamSubscription<String>? _errors;
  List<Channel> _items = [];
  Set<String> _favorites = {};
  SourceConfig? _source;
  Channel? _selected;
  bool _fullScreen = false, _epgBusy = false;
  LiveView _liveView = LiveView.list;
  Map<String, List<Programme>> _epg = {};
  String _epgUrl = '';
  int _epgRequest = 0;
  DateTime _now = DateTime.now();
  Timer? _clock;
  String _kind = 'live', _category = '', _query = '';
  String? _notice;
  bool _busy = false, _favoritesOnly = false;
  final _categoryCounts = <String, Map<String, int>>{};

  @override
  void initState() {
    super.initState();
    _errors = _player.stream.error.listen((_) {
      if (mounted) { setState(() => _notice = 'Yayın açılamadı. Sağlayıcı erişimini ve bağlantınızı kontrol edin.'); }
    });
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) { setState(() => _now = DateTime.now()); }
    });
    _restore();
  }
  @override
  void dispose() {
    _clock?.cancel(); _errors?.cancel(); _player.dispose(); _client.close(); _search.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final stored = await Future.wait([_vault.read(key: 'source'), _vault.read(key: 'favorites')]);
      if (!mounted) { return; }
      if (stored[1] != null) { _favorites = (jsonDecode(stored[1]!) as List).whereType<String>().toSet(); }
      if (stored[0] != null) {
        final config = SourceConfig.fromJson(Map<String, dynamic>.from(jsonDecode(stored[0]!) as Map));
        await _load(config, writeStorage: false);
        final savedEpg = await _vault.read(key: 'epg');
        if (mounted && savedEpg != null && _source?.url == config.url) {
          final saved = jsonDecode(savedEpg) as Map;
          if (saved['source'] == config.url && saved['url'] is String) { await _loadEpg(saved['url'] as String); }
        }
      }
    } catch (_) {
      if (mounted) { setState(() => _notice = 'Cihazdaki kaynak kaydı okunamadı. Kaynağı yeniden ekleyebilirsiniz.'); }
    } finally { if (mounted) { setState(() => _busy = false); } }
  }

  void _indexCategories() {
    _categoryCounts.clear();
    for (final kind in kinds.keys) {
      final counts = {for (final name in categoriesFor(_items, kind)) name: 0};
      for (final item in _items.where((c) => c.kind == kind)) {
        final category = categoryOf(item); counts[category] = (counts[category] ?? 0) + 1;
      }
      _categoryCounts[kind] = counts;
    }
  }

  String _safeError(Object error) {
    if (error is FormatException) { return error.message; }
    if (error is HandshakeException) { return 'HTTPS sertifikası doğrulanamadı. Sağlayıcının geçerli sunucu adresini kullanın.'; }
    if (error is TimeoutException) { return 'Sağlayıcı yanıtı zaman aşımına uğradı. Yeniden deneyin.'; }
    return 'Kaynak yüklenemedi. Sunucu adresini, bağlantınızı ve hesap bilgilerini kontrol edin.';
  }

  Future<void> _load(SourceConfig? config, {List<Channel>? local, bool remember = true, bool writeStorage = true}) async {
    setState(() { _busy = true; _notice = null; });
    try {
      final service = SourceService(_client);
      final List<Channel> items;
      if (local != null) {
        items = local;
      } else {
        if (config == null) { throw const FormatException('Önce bir kaynak ekleyin.'); }
        items = await (config.type == 'xtream' ? service.xtream(config) : service.m3u(config.url));
      }
      _epgRequest++;
      await _player.stop();
      if (!mounted) { return; }
      setState(() {
        _items = items; _source = config; _selected = null; _fullScreen = false; _epg = {}; _epgUrl = ''; _epgBusy = false; _kind = 'live';
        if (!items.any((c) => c.kind == 'live')) { _kind = items.first.kind; }
        _category = ''; _query = ''; _search.clear(); _favoritesOnly = false;
        _indexCategories(); _notice = service.warnings.isEmpty ? null : service.warnings.join(' ');
      });
      if (writeStorage) {
        try {
          if (remember && config != null) { await _vault.write(key: 'source', value: jsonEncode(config.toJson())); }
          else { await _vault.delete(key: 'source'); }
        } catch (_) {
          if (mounted) { setState(() => _notice = 'Kaynak açıldı ancak cihazda kayıt güncellenemedi. Önceki kayıt korunmuş olabilir.'); }
        }
      }
    } catch (error) {
      if (mounted) { setState(() => _notice = _safeError(error)); }
    } finally { if (mounted) { setState(() => _busy = false); } }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['m3u', 'm3u8']);
      if (result == null || !mounted) { return; }
      final file = result.files.single;
      if (file.size > maxPlaylistBytes) { throw const FormatException('Dosya çok büyük. En fazla 100 MB destekleniyor.'); }
      final Stream<List<int>> stream;
      if (file.path != null) {
        stream = File(file.path!).openRead();
      } else if (file.bytes != null) {
        stream = Stream.value(file.bytes!);
      } else {
        throw const FormatException('Dosya okunamadı.');
      }
      setState(() => _busy = true);
      try {
        final items = await parseM3uStream(stream);
        if (!mounted) { return; }
        await _load(null, local: items, remember: false);
      } finally {
        if (mounted) { setState(() => _busy = false); }
      }
    } catch (error) { if (mounted) { setState(() => _notice = _safeError(error)); } }
  }

  Future<void> _addSource() async {
    final url = TextEditingController(text: _source?.url ?? '');
    final user = TextEditingController(text: _source?.username ?? '');
    final password = TextEditingController();
    var xtream = _source?.type == 'xtream', remember = true;
    String? error;
    final input = await showDialog<_SourceInput>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, change) => AlertDialog(
        title: const Text('Kaynak ekle'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('M3U')),
            ButtonSegment(value: true, label: Text('Xtream'))], selected: {xtream},
            onSelectionChanged: (s) => change(() { xtream = s.first; error = null; })),
          const SizedBox(height: 18),
          TextField(controller: url, keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false,
            decoration: InputDecoration(labelText: xtream ? 'Sunucu adresi' : 'M3U bağlantısı', hintText: 'http:// veya https://', border: const OutlineInputBorder())),
          if (xtream) ...[
            const SizedBox(height: 12),
            TextField(controller: user, autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Kullanıcı adı', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder())),
          ],
          const SizedBox(height: 12),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: remember, title: const Text('Bu cihazda hatırla'),
            subtitle: const Text('Kaynak bilgileri Android güvenli deposunda saklanır.'), onChanged: (v) => change(() => remember = v ?? false)),
          const Text('Doğrudan sağlayıcıya bağlanır. HTTP bağlantılar şifreli değildir.', style: TextStyle(fontSize: 12)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.orangeAccent))),
          if (!xtream) TextButton.icon(icon: const Icon(Icons.folder_open), label: const Text('M3U dosyası seç'),
            onPressed: () => Navigator.pop(context, const _SourceInput(file: true))),
          if (!xtream) const Text('Dosya listeleri bu oturumda kullanılır. Kalıcı kayıt için bağlantı ekleyin.', style: TextStyle(fontSize: 11)),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () {
            try {
              serverUri(url.text);
              if (xtream && (user.text.trim().isEmpty || password.text.isEmpty)) { throw const FormatException('Kullanıcı adı ve şifre gerekli.'); }
              Navigator.pop(context, _SourceInput(config: SourceConfig(type: xtream ? 'xtream' : 'm3u',
                url: url.text.trim(), username: user.text.trim(), password: password.text), remember: remember));
            } catch (e) { change(() => error = _safeError(e)); }
          }, child: const Text('Yükle'))],
      ),
    ));
    url.dispose(); user.dispose(); password.dispose();
    if (!mounted || input == null) { return; }
    if (input.file) { await _pickFile(); }
    else { await _load(input.config, remember: input.remember); }
  }

  Future<void> _removeSource() async {
    try {
      await _vault.delete(key: 'source'); await _vault.delete(key: 'epg'); await _player.stop();
      if (!mounted) { return; }
      setState(() { _source = null; _items = []; _selected = null; _fullScreen = false; _epg = {}; _epgUrl = ''; _epgRequest++; _epgBusy = false; _category = ''; _query = ''; _search.clear(); _indexCategories(); _notice = 'Kaynak kaydı silindi.'; });
    } catch (_) { if (mounted) { setState(() => _notice = 'Kaynak kaydı silinemedi. Yeniden deneyin.'); } }
  }

  Future<void> _toggleFavorite(Channel channel) async {
    setState(() { if (!_favorites.add(channel.key)) { _favorites.remove(channel.key); } });
    try { await _vault.write(key: 'favorites', value: jsonEncode(_favorites.toList())); }
    catch (_) { if (mounted) { setState(() => _notice = 'Favori bu oturumda güncellendi ancak kalıcı kaydedilemedi.'); } }
  }

  Future<void> _select(Channel channel) async {
    if (channel.seriesId != null && _source?.type == 'xtream') {
      setState(() => _busy = true);
      try {
        final episodes = await SourceService(_client).episodes(_source!, channel);
        if (!mounted) { return; }
        final selected = await showDialog<Channel>(context: context, builder: (context) => AlertDialog(
          title: Text(channel.name), content: SizedBox(width: 600, height: 440,
            child: ListView.builder(itemCount: episodes.length, itemBuilder: (context, index) {
              final item = episodes[index];
              return ListTile(autofocus: index == 0, leading: const Icon(Icons.play_circle_outline),
                title: Text(item.name), subtitle: Text('Sezon ${item.season}'), onTap: () => Navigator.pop(context, item));
            })),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
        ));
        if (selected != null && mounted) { await _play(selected); }
      } catch (error) { if (mounted) { setState(() => _notice = _safeError(error)); } }
      finally { if (mounted) { setState(() => _busy = false); } }
    } else { await _play(channel); }
  }
  Future<void> _play(Channel channel, {bool fullscreen = true}) async {
    setState(() { _selected = channel; _fullScreen = fullscreen; _notice = null; });
    try { await _player.open(Media(channel.url)); }
    catch (_) { if (mounted) { setState(() => _notice = 'Yayın başlatılamadı. Bağlantıyı kontrol edin.'); } }
  }
  Future<void> _backToCatalog() async {
    if (_selected?.kind == 'live') {
      setState(() => _fullScreen = false);
    } else {
      await _player.stop();
      if (mounted) { setState(() { _selected = null; _fullScreen = false; }); }
    }
  }
  void _filter(String kind, String category) {
    if (kind != 'live' && _selected != null) {
      _player.stop(); _selected = null;
    }
    setState(() { _kind = kind; _category = category; _query = ''; _search.clear(); _favoritesOnly = false; });
    _scaffoldKey.currentState?.closeDrawer();
  }

  Widget _navigation() => Drawer(child: SafeArea(child: ListView(children: [
    const Padding(padding: EdgeInsets.all(24), child: Text('IP360', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: mint))),
    for (final entry in kinds.entries) ExpansionTile(key: PageStorageKey(entry.key),
      initiallyExpanded: entry.key == _kind, leading: Icon(kindIcons[entry.key], color: entry.key == _kind ? mint : null),
      title: Text(entry.value), children: [
        ListTile(title: const Text('Tümü'), selected: _kind == entry.key && _category.isEmpty,
          onTap: () => _filter(entry.key, '')),
        for (final category in (_categoryCounts[entry.key] ?? {for (final c in categoriesFor([], entry.key)) c: 0}).entries)
          ListTile(dense: true, title: Text(category.key, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text('${category.value}'), selected: _kind == entry.key && _category == category.key,
            onTap: () => _filter(entry.key, category.key)),
      ]),
    const Divider(),
    ListTile(leading: const Icon(Icons.star_outline), title: const Text('Favoriler'), selected: _favoritesOnly,
      onTap: () { setState(() => _favoritesOnly = !_favoritesOnly); _scaffoldKey.currentState?.closeDrawer(); }),
    ListTile(leading: const Icon(Icons.playlist_play), title: const Text('Kaynaklar'), onTap: _sources),
    ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Ayarlar'), onTap: _settings),
    ListTile(leading: const Icon(Icons.info_outline), title: const Text('Gizlilik ve kullanım'), onTap: _help),
  ])));

  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('IP360 hakkında'), content: const SingleChildScrollView(child: Text(
      'Uygulama yayın veya abonelik içermez. Kullanım hakkına sahip olduğunuz kaynakları ekleyin.\n\n'
      'Yayınlar doğrudan cihazınızdan sağlayıcıya gider. Sağlayıcı IP adresinizi ve yayın isteklerinizi görebilir. HTTP bağlantılar şifrelenmez.\n\n'
      'Hatırlanan M3U/Xtream hesapları ve favoriler cihazın Android güvenli deposunda tutulur. Kaynağı sil seçeneğiyle kaldırabilirsiniz. Bu koruma, kilidi açık cihazı kullanan birinin yayını açmasını engellemez.\n\n'
      'Telefon/tablette dokunma, TV’de yön tuşları ve OK ile gezinilir. Geri tuşu oynatıcıdan kataloğa döner. DRM ve tüm kodeklerin çalışması garanti edilmez.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
  ));

  Widget _noticeWidget() => _notice == null ? const SizedBox.shrink() : MaterialBanner(content: Text(_notice!),
    actions: [TextButton(onPressed: () => setState(() => _notice = null), child: const Text('Kapat'))]);

  String _suggestEpg() {
    if (_epgUrl.isNotEmpty) { return _epgUrl; }
    if (_source?.type != 'xtream') { return ''; }
    final base = serverUri(_source!.url);
    return base.replace(path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/xmltv.php',
      queryParameters: {'username': _source!.username, 'password': _source!.password}).toString();
  }

  Future<void> _configureEpg() async {
    final controller = TextEditingController(text: _suggestEpg());
    final url = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Yayın rehberi • XMLTV'), content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Sağlayıcının XMLTV bağlantısını ekle. Kanallar tvg-id / EPG kimliği ile eşleştirilir. Rehber yoksa kanal izleme devam eder.'),
        const SizedBox(height: 16), TextField(controller: controller, keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'XMLTV bağlantısı', hintText: 'https://…/epg.xml')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Rehberi yükle'))]));
    controller.dispose();
    if (url == null || !mounted) { return; }
    await _loadEpg(url);
  }

  Future<void> _loadEpg(String url) async {
    final request = ++_epgRequest;
    setState(() { _epgBusy = true; _notice = null; });
    try {
      final data = await EpgService(_client).load(url);
      if (!mounted || request != _epgRequest) { return; }
      setState(() { _epg = data; _epgUrl = url; _now = DateTime.now();
        _notice = data.isEmpty ? 'XMLTV dosyasında geçerli program bulunamadı.' : 'Yayın rehberi yüklendi.'; });
      if (_source != null) {
        await _vault.write(key: 'epg', value: jsonEncode({'source': _source!.url, 'url': url}));
      }
    } catch (_) {
      if (mounted && request == _epgRequest) { setState(() => _notice = 'Yayın rehberi yüklenemedi. Geçerli sertifikalı bir XMLTV bağlantısı kullanın (en fazla 30 MB).'); }
    } finally {
      if (mounted && request == _epgRequest) { setState(() => _epgBusy = false); }
    }
  }

  Future<void> _sources() async {
    _scaffoldKey.currentState?.closeDrawer();
    await showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Kaynaklar'),
      content: Text(_source == null ? (_items.isEmpty ? 'Henüz kaynak eklenmedi.' : 'Cihazdan açılan M3U dosyası • bu oturum') :
        '${_source!.type == 'xtream' ? 'Xtream' : 'M3U'} • ${Uri.tryParse(_source!.url)?.host ?? ''}\n${_items.length} içerik\n\nYeni kaynak mevcut kataloğun yerine açılır.'),
      actions: [TextButton(onPressed: () { Navigator.pop(context); _removeSource(); }, child: const Text('Kaynağı sil')),
        FilledButton(onPressed: () { Navigator.pop(context); _addSource(); }, child: const Text('Kaynak ekle'))]));
  }

  Future<void> _settings() async {
    _scaffoldKey.currentState?.closeDrawer();
    await showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Ayarlar'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.calendar_view_week), title: const Text('Yayın rehberi'), subtitle: const Text('XMLTV kaynağı ekle veya güncelle'),
          onTap: () { Navigator.pop(context); _configureEpg(); }),
        ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('Gizlilik ve kullanım'), onTap: () { Navigator.pop(context); _help(); }),
        const ListTile(leading: Icon(Icons.info_outline), title: Text('IP360 0.2.0'), subtitle: Text('Telefon • Tablet • Android TV')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))]));
  }

  Future<void> _details(Channel channel) async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(channel.name), content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (channel.logo.isNotEmpty) SizedBox(height: 220, child: Image.network(channel.logo, fit: BoxFit.contain,
          errorBuilder: (_, error, stack) => const Icon(Icons.movie_outlined, size: 80, color: mint))),
        const SizedBox(height: 16), Text(channel.group), const SizedBox(height: 12),
        Text(channel.description.isEmpty ? 'Bu içerik için açıklama bulunmuyor.' : channel.description),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        FilledButton.icon(icon: const Icon(Icons.play_arrow), label: Text(channel.seriesId != null ? 'Bölümleri göster' : 'Oynat'),
          onPressed: () { Navigator.pop(context); _select(channel); })]));
  }

  Future<void> _chooseLive(Channel channel) async {
    if (_selected?.key == channel.key) {
      setState(() => _fullScreen = true);
    } else {
      await _play(channel, fullscreen: false);
    }
  }

  Widget _preview() {
    final channel = _selected;
    final programmes = channel == null ? <Programme>[] : _epg[channel.epgId] ?? <Programme>[];
    final current = currentProgramme(programmes, _now);
    final next = programmes.where((p) => p.start.isAfter(_now)).firstOrNull;
    return LayoutBuilder(builder: (context, size) => SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ConstrainedBox(constraints: BoxConstraints(maxHeight: size.maxHeight < 260 ? 105 : 280), child: AspectRatio(aspectRatio: 16 / 9,
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ColoredBox(color: Colors.black, child: channel == null ?
            const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_outline, color: mint, size: 40),
              SizedBox(height: 8), Text('Önizleme için kanal seç', style: TextStyle(color: Colors.white54, fontSize: 12))])) : Video(controller: _video))))),
        const SizedBox(height: 14), Text(channel?.name ?? 'Canlı TV', maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        if (channel != null) ...[
          const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => setState(() => _fullScreen = true), icon: const Icon(Icons.fullscreen), label: const Text('Tam ekran')),
            IconButton(tooltip: 'Oynat / duraklat', onPressed: _player.playOrPause, icon: const Icon(Icons.pause_circle_outline)),
            IconButton(tooltip: 'Yeniden dene', onPressed: () => _play(channel, fullscreen: false), icon: const Icon(Icons.refresh)),
          ]),
        ],
        const SizedBox(height: 20), const Text('ŞİMDİ', style: TextStyle(color: mint, fontSize: 11, letterSpacing: 2)), const SizedBox(height: 8),
        Text(current?.title ?? 'Program bilgisi yok', style: const TextStyle(fontSize: 16)),
        if (current != null) ...[const SizedBox(height: 6), Text('${programmeTime(current.start)} – ${programmeTime(current.end)}', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 10), LinearProgressIndicator(value: (_now.difference(current.start).inSeconds / current.end.difference(current.start).inSeconds).clamp(0, 1)),
          if (current.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(current.description, maxLines: 5, overflow: TextOverflow.ellipsis))],
        const SizedBox(height: 20), const Text('SIRADAKİ', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 8), Text(next == null ? 'Program bilgisi yok' : '${programmeTime(next.start)}  ${next.title}'),
        const SizedBox(height: 16), TextButton.icon(onPressed: _epgBusy ? null : _configureEpg,
          icon: const Icon(Icons.calendar_view_week, size: 18), label: Text(_epgBusy ? 'Rehber yükleniyor…' : 'Yayın rehberi kaynağı')),
      ]))));
  }

  Widget _empty() => Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.live_tv, size: 64, color: mint), const SizedBox(height: 24),
      Text(_items.isEmpty ? 'Ekranın, senin yayınların.' : 'Eşleşen içerik bulunamadı.', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)), const SizedBox(height: 10),
      Text(_items.isEmpty ? 'M3U veya Xtream kaynağını ekleyerek başla.' : 'Başka bir kategori seç veya aramayı temizle.', textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54)), const SizedBox(height: 24),
      FilledButton.icon(onPressed: _busy ? null : _addSource, icon: const Icon(Icons.add), label: const Text('Kaynak ekle')),
    ]))));

  @override
  Widget build(BuildContext context) {
    if (_selected != null && _fullScreen) {
      return PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) { if (!didPop) { _backToCatalog(); } },
        child: Shortcuts(shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): _PlaybackIntent(),
          SingleActivator(LogicalKeyboardKey.mediaPlayPause): _PlaybackIntent(),
        }, child: Actions(actions: {_PlaybackIntent: CallbackAction<_PlaybackIntent>(onInvoke: (_) { _player.playOrPause(); return null; })},
          child: Scaffold(appBar: AppBar(leading: IconButton(autofocus: true, tooltip: 'Kataloğa dön', onPressed: _backToCatalog, icon: const Icon(Icons.arrow_back)),
            title: Text(_selected!.name, overflow: TextOverflow.ellipsis), actions: [
              IconButton(tooltip: 'Oynat / duraklat', onPressed: _player.playOrPause, icon: const Icon(Icons.pause_circle_outline)),
              IconButton(tooltip: 'Yeniden dene', onPressed: () => _play(_selected!), icon: const Icon(Icons.refresh)),
            ]), body: Column(children: [_noticeWidget(), Expanded(child: ColoredBox(color: Colors.black, child: Video(controller: _video)))])),
        )));
    }
    final visible = _items.where((c) => c.kind == _kind && (_category.isEmpty || categoryOf(c) == _category) &&
      normalize(c.name).contains(normalize(_query)) && (!_favoritesOnly || _favorites.contains(c.key))).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final catalog = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 8), child: Row(children: [
        Expanded(child: Text(_favoritesOnly ? 'Favoriler' : _category.isEmpty ? kinds[_kind]! : _category,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
        Text('${visible.length} içerik', style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: TextField(controller: _search,
        onChanged: (v) => setState(() => _query = v), decoration: const InputDecoration(isDense: true,
          prefixIcon: Icon(Icons.search), hintText: 'Kanal, film veya dizi ara'))),
      if (_kind == 'live') Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: SizedBox(width: double.infinity,
        child: SegmentedButton<LiveView>(showSelectedIcon: false, segments: const [
          ButtonSegment(value: LiveView.logos, icon: Icon(Icons.grid_view, size: 16), label: Text('Logolar')),
          ButtonSegment(value: LiveView.list, icon: Icon(Icons.view_list, size: 16), label: Text('Liste')),
          ButtonSegment(value: LiveView.guide, icon: Icon(Icons.calendar_view_week, size: 16), label: Text('Rehber'))],
          selected: {_liveView}, onSelectionChanged: (v) => setState(() => _liveView = v.first)))),
      Expanded(child: visible.isEmpty ? _empty() : _kind == 'live' ? LiveWorkspace(channels: visible, view: _liveView,
        preview: _preview(), selected: _selected, epg: _epg, now: _now, favorites: _favorites,
        onSelect: _chooseLive, onFavorite: _toggleFavorite, onEpg: _configureEpg) :
        GridView.builder(padding: const EdgeInsets.all(16), itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 210,
            childAspectRatio: .58, crossAxisSpacing: 16, mainAxisSpacing: 16),
          itemBuilder: (context, index) => _MediaCard(key: ValueKey(visible[index].key), channel: visible[index],
            favorite: _favorites.contains(visible[index].key), autofocus: index == 0,
            onTap: () => _details(visible[index]), onFavorite: () => _toggleFavorite(visible[index])))),
    ]);
    return Scaffold(key: _scaffoldKey, drawer: wide ? null : _navigation(),
      appBar: AppBar(title: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_fill, color: mint), SizedBox(width: 8),
        Text('IP360', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700))]), actions: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text(programmeTime(_now), style: const TextStyle(color: Colors.white54, fontSize: 13)))),
        IconButton(tooltip: 'Kaynaklar', onPressed: _busy ? null : _sources, icon: const Icon(Icons.playlist_add)),
        IconButton(tooltip: 'Ayarlar', onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
      ]), body: SafeArea(child: Column(children: [
        if (_busy || _epgBusy) const LinearProgressIndicator(minHeight: 2), _noticeWidget(),
        Expanded(child: Row(children: [if (wide) SizedBox(width: 230, child: _navigation()), Expanded(child: catalog)])),
      ])));
  }

}

class _MediaCard extends StatefulWidget {
  const _MediaCard({super.key, required this.channel, required this.favorite, required this.autofocus, required this.onTap, required this.onFavorite});
  final Channel channel;
  final bool favorite, autofocus;
  final VoidCallback onTap, onFavorite;
  @override
  State<_MediaCard> createState() => _MediaCardState();
}
class _MediaCardState extends State<_MediaCard> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final fallback = Center(child: Icon(kindIcons[channel.kind], size: 46, color: mint));
    return Card(clipBehavior: Clip.antiAlias, color: const Color(0xFF19232E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: focused ? mint : const Color(0xFF2B3744), width: focused ? 3 : 1)),
      child: InkWell(autofocus: widget.autofocus, onFocusChange: (v) => setState(() => focused = v), onTap: widget.onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: channel.logo.isEmpty ? fallback : Image.network(channel.logo,
            fit: channel.kind == 'live' ? BoxFit.contain : BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback)),
          Padding(padding: const EdgeInsets.fromLTRB(10, 7, 4, 7), child: Row(children: [
            Expanded(child: Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            IconButton(tooltip: 'Favori', onPressed: widget.onFavorite, icon: Icon(widget.favorite ? Icons.star : Icons.star_outline,
              color: widget.favorite ? Colors.amber : Colors.white54, size: 21)),
          ])),
        ])));
  }
}
