import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../epg.dart';
import '../source.dart';
import 'player_chrome.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.player, required this.controller, required this.channel,
    required this.programmes, required this.favorite, required this.onBack, required this.onHistory,
    required this.onFavorite, required this.onRetry, this.onGuide, this.onPrevious, this.onNext,
    this.notice, this.channelNumber});
  final Player player;
  final VideoController controller;
  final Channel channel;
  final List<Programme> programmes;
  final bool favorite;
  final VoidCallback onBack, onHistory, onFavorite, onRetry;
  final VoidCallback? onGuide, onPrevious, onNext;
  final String? notice;
  final int? channelNumber;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _timer;
  double? _fps;
  bool _reading = false;
  BoxFit _fit = BoxFit.contain;
  String? _trackError;
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final p = widget.player;
    for (final stream in <Stream<dynamic>>[p.stream.playing, p.stream.position, p.stream.duration, p.stream.buffering,
      p.stream.width, p.stream.height, p.stream.videoParams, p.stream.audioParams, p.stream.track, p.stream.tracks]) {
      _subscriptions.add(stream.listen((_) { if (mounted) { setState(() {}); } }));
    }
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) { setState(() {}); _readFps(); }
    });
    _readFps();
  }
  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.key != widget.channel.key) { _fps = null; _trackError = null; }
  }
  Future<void> _readFps() async {
    if (_reading) { return; }
    final platform = widget.player.platform;
    if (platform is! NativePlayer) { return; }
    final key = widget.channel.key;
    _reading = true;
    try {
      final value = double.tryParse(await platform.getProperty('container-fps').timeout(const Duration(seconds: 2)));
      if (mounted && key == widget.channel.key) { setState(() => _fps = value); }
    } catch (_) { /* Bilinmeyen FPS için etiket gösterilmez. */ }
    finally { _reading = false; }
  }
  @override
  void dispose() {
    _timer?.cancel();
    for (final subscription in _subscriptions) { subscription.cancel(); }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
  Future<void> _audio(AudioTrack track) async {
    try { await widget.player.setAudioTrack(track); }
    catch (_) { if (mounted) { setState(() => _trackError = 'Ses parçası değiştirilemedi.'); } }
  }
  Future<void> _subtitle(SubtitleTrack track) async {
    try { await widget.player.setSubtitleTrack(track); }
    catch (_) { if (mounted) { setState(() => _trackError = 'Altyazı değiştirilemedi.'); } }
  }
  Future<void> _tracks() async {
    final state = widget.player.state;
    await showDialog<void>(context: context, builder: (context) => SimpleDialog(title: const Text('Ses / Altyazı'), children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('SES', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ListTile(title: const Text('Otomatik'), onTap: () { Navigator.pop(context); _audio(AudioTrack.auto()); }),
      for (final track in state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no'))
        ListTile(title: Text(track.title ?? track.language ?? 'Ses ${track.id}'), trailing: state.track.audio.id == track.id ? const Icon(Icons.check) : null,
          onTap: () { Navigator.pop(context); _audio(track); }),
      const Divider(), const Padding(padding: EdgeInsets.all(16), child: Text('ALTYAZI', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ListTile(title: const Text('Kapalı'), onTap: () { Navigator.pop(context); _subtitle(SubtitleTrack.no()); }),
      ListTile(title: const Text('Otomatik'), onTap: () { Navigator.pop(context); _subtitle(SubtitleTrack.auto()); }),
      for (final track in state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'))
        ListTile(title: Text(track.title ?? track.language ?? 'Altyazı ${track.id}'), trailing: state.track.subtitle.id == track.id ? const Icon(Icons.check) : null,
          onTap: () { Navigator.pop(context); _subtitle(track); }),
    ]));
  }
  Future<void> _fitDialog() async {
    final fit = await showDialog<BoxFit>(context: context, builder: (context) => SimpleDialog(title: const Text('Görüntü oranı'), children: [
      for (final entry in {BoxFit.contain: 'Orijinal oran • ekrana sığdır', BoxFit.cover: 'Ekranı doldur • kenarlardan kırp', BoxFit.fill: 'Ekrana yay • oranı esnet'}.entries)
        ListTile(title: Text(entry.value), trailing: _fit == entry.key ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, entry.key)),
    ]));
    if (fit != null && mounted) { setState(() => _fit = fit); }
  }
  @override
  Widget build(BuildContext context) => PlayerChrome(key: ValueKey(widget.channel.key),
    video: Video(controller: widget.controller, controls: NoVideoControls, fit: _fit),
    channel: widget.channel, state: widget.player.state, now: DateTime.now(), programmes: widget.programmes,
    favorite: widget.favorite, onBack: widget.onBack, onPlayPause: widget.player.playOrPause,
    onRetry: widget.onRetry, onHistory: widget.onHistory, onFavorite: widget.onFavorite, onTracks: _tracks,
    onFit: _fitDialog, onSeek: (duration) => widget.player.seek(duration), onGuide: widget.onGuide,
    onPrevious: widget.onPrevious, onNext: widget.onNext, fps: _fps, notice: widget.notice ?? _trackError,
    channelNumber: widget.channelNumber);
}
