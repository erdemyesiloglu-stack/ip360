import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../epg.dart';
import '../source.dart';
import 'playback_info.dart';

class PlayerChrome extends StatefulWidget {
  const PlayerChrome({super.key, required this.video, required this.channel, required this.state,
    required this.now, required this.programmes, required this.favorite, required this.onBack,
    required this.onPlayPause, required this.onRetry, required this.onHistory, required this.onFavorite,
    required this.onTracks, required this.onFit, required this.onSeek, this.onGuide,
    this.onPrevious, this.onNext, this.fps, this.notice, this.channelNumber,
    this.hideAfter = const Duration(seconds: 7)});
  final Widget video;
  final Channel channel;
  final PlayerState state;
  final DateTime now;
  final List<Programme> programmes;
  final bool favorite;
  final VoidCallback onBack, onPlayPause, onRetry, onHistory, onFavorite, onTracks, onFit;
  final VoidCallback? onGuide, onPrevious, onNext;
  final ValueChanged<Duration> onSeek;
  final double? fps;
  final String? notice;
  final int? channelNumber;
  final Duration hideAfter;
  @override
  State<PlayerChrome> createState() => _PlayerChromeState();
}

class _PlayerChromeState extends State<PlayerChrome> {
  bool _visible = true;
  Timer? _hide;
  final _rootFocus = FocusNode();
  final _playFocus = FocusNode();
  double? _scrub;
  @override
  void initState() { super.initState(); _arm(); }
  @override
  void dispose() { _hide?.cancel(); _rootFocus.dispose(); _playFocus.dispose(); super.dispose(); }
  void _arm() {
    _hide?.cancel();
    _hide = Timer(widget.hideAfter, () { if (mounted) { _setVisible(false); } });
  }
  void _setVisible(bool visible) {
    setState(() => _visible = visible);
    if (visible) { _arm(); _playFocus.requestFocus(); }
    else { _hide?.cancel(); _rootFocus.requestFocus(); }
  }
  void _interact(VoidCallback action) { _arm(); action(); }
  void _back() { if (_visible) { _setVisible(false); } else { widget.onBack(); } }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) { return KeyEventResult.ignored; }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.space) {
      _setVisible(true); widget.onPlayPause(); return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) { _back(); return KeyEventResult.handled; }
    if (!_visible && [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight].contains(key)) {
      _setVisible(true); return KeyEventResult.handled;
    }
    _arm();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) { if (!didPop) { _back(); } },
    child: Focus(focusNode: _rootFocus, autofocus: true, onKeyEvent: _key,
      child: Scaffold(backgroundColor: Colors.black, body: Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: widget.video),
        Positioned.fill(child: GestureDetector(key: const Key('player-surface'), behavior: HitTestBehavior.opaque,
          onTap: () => _setVisible(!_visible))),
        if (widget.state.buffering) const IgnorePointer(child: Center(child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2)))),
        if (!_visible && widget.notice != null) Positioned(left: 20, right: 20, bottom: 20,
          child: Center(child: TextButton.icon(onPressed: () => _setVisible(true), icon: const Icon(Icons.error_outline),
            label: const Text('Yayın açılamadı • Kontrolleri aç')))),
        if (_visible) Positioned.fill(child: Listener(onPointerDown: (_) => _hide?.cancel(), onPointerUp: (_) => _arm(), onPointerCancel: (_) => _arm(),
          child: SafeArea(child: LayoutBuilder(builder: (context, box) => Column(children: [
            _header(box.maxWidth), const Spacer(),
            ConstrainedBox(constraints: BoxConstraints(maxHeight: box.maxHeight > 90 ? box.maxHeight - 84 : box.maxHeight),
              child: _panel(box.maxWidth)),
          ]))))),
      ]))));

  Widget _header(double width) => DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter,
    end: Alignment.bottomCenter, colors: [Color(0xDD000000), Color(0x00000000)])),
    child: Padding(padding: const EdgeInsets.fromLTRB(8, 6, 16, 20), child: Row(children: [
      IconButton(tooltip: 'Kanallara dön', onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
      Expanded(child: Text(categoryOf(widget.channel), maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: width < 600 ? 14 : 20))), const SizedBox(width: 8),
      Text(playbackDate(widget.now), style: TextStyle(fontSize: width < 600 ? 12 : 18, color: Colors.white70)),
    ])));

  Widget _panel(double width) {
    final compact = width < 600;
    final current = currentProgramme(widget.programmes, widget.now);
    final next = widget.programmes.where((p) => p.start.isAfter(widget.now)).firstOrNull;
    final live = widget.channel.kind == 'live';
    final badges = technicalBadges(width: widget.state.width ?? widget.state.videoParams.w,
      height: widget.state.height ?? widget.state.videoParams.h, fps: widget.fps, audioChannels: widget.state.audioParams.channelCount);
    return DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter,
      end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xE6000000), Color(0xF5000000)], stops: [0, .2, 1])),
      child: SingleChildScrollView(child: Padding(padding: EdgeInsets.fromLTRB(compact ? 16 : 36, 30, compact ? 16 : 36, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.notice != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.notice!, style: const TextStyle(color: Colors.orangeAccent))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: compact ? 58 : 108, height: compact ? 58 : 90, child: widget.channel.logo.isEmpty ?
              const Icon(Icons.live_tv, color: Colors.white60, size: 42) : Image.network(widget.channel.logo, fit: BoxFit.contain,
                cacheWidth: 240, errorBuilder: (_, error, stack) => const Icon(Icons.live_tv, color: Colors.white60, size: 42))),
            const SizedBox(width: 18), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 5), Text(live ? current?.title ?? 'Program bilgisi yok' : widget.channel.name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 21 : 30, fontWeight: FontWeight.w600)),
              if (live && current != null) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 16, runSpacing: 4, children: [
                Text('${programmeTime(current.start)} – ${programmeTime(current.end)}', style: const TextStyle(color: Colors.white70)),
                Text('${(current.end.difference(widget.now).inSeconds / 60).ceil()} dk kaldı', style: const TextStyle(color: Colors.white70)),
              ])),
              if (live) Padding(padding: const EdgeInsets.only(top: 7), child: Text(next == null ? 'Sıradaki: Bilgi yok' :
                '${programmeTime(next.start)} – ${programmeTime(next.end)}  ${next.title}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13))),
            ])),
            if (widget.channelNumber != null) Padding(padding: const EdgeInsets.only(left: 12), child: Text('${widget.channelNumber}',
              style: TextStyle(color: Colors.white60, fontSize: compact ? 18 : 28))),
          ]), const SizedBox(height: 12),
          if (badges.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: [for (final badge in badges)
            DecoratedBox(decoration: BoxDecoration(color: const Color(0xDD45515B), borderRadius: BorderRadius.circular(3)),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), child: Text(badge, style: const TextStyle(fontSize: 11))))]),
          const SizedBox(height: 14),
          if (live) ...[
            Row(children: [const Icon(Icons.circle, size: 8, color: Colors.redAccent), const SizedBox(width: 6),
              const Text('CANLI', style: TextStyle(fontSize: 10, letterSpacing: 1.2)), const Spacer(),
              if (current != null) const Text('Program ilerlemesi', style: TextStyle(color: Colors.white38, fontSize: 10))]),
            const SizedBox(height: 8),
            if (current != null) LinearProgressIndicator(key: const Key('programme-progress'), minHeight: 3, color: const Color(0xFF2196F3), backgroundColor: Colors.white24,
              value: (widget.now.difference(current.start).inSeconds / current.end.difference(current.start).inSeconds).clamp(0.0, 1.0)),
          ] else _seekBar(),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (widget.onPrevious != null) IconButton(tooltip: 'Önceki kanal', onPressed: () => _interact(widget.onPrevious!), icon: const Icon(Icons.skip_previous)),
            IconButton(focusNode: _playFocus, autofocus: true, tooltip: widget.state.playing ? 'Duraklat' : 'Oynat',
              onPressed: () => _interact(widget.onPlayPause), iconSize: 38, icon: Icon(widget.state.playing ? Icons.pause_circle_outline : Icons.play_circle_outline)),
            if (widget.onNext != null) IconButton(tooltip: 'Sonraki kanal', onPressed: () => _interact(widget.onNext!), icon: const Icon(Icons.skip_next)),
            IconButton(tooltip: 'Paneli gizle', onPressed: () => _setVisible(false), icon: const Icon(Icons.keyboard_arrow_down)),
          ]), const SizedBox(height: 8),
          SizedBox(height: compact ? 84 : 108, child: ListView(scrollDirection: Axis.horizontal, children: [
            if (widget.onGuide != null) _action(Icons.view_list, 'TV rehberi', widget.onGuide!, compact),
            _action(Icons.history, 'Son izlenenler', widget.onHistory, compact),
            _action(widget.favorite ? Icons.star : Icons.star_outline, widget.favorite ? 'Favoriden çıkar' : 'Favoriye ekle', widget.onFavorite, compact),
            _action(Icons.audiotrack, 'Ses / Altyazı', widget.onTracks, compact),
            _action(Icons.aspect_ratio, 'Görüntü oranı', widget.onFit, compact),
            _action(Icons.refresh, 'Yeniden bağlan', widget.onRetry, compact),
          ])),
        ]))));
  }

  Widget _seekBar() {
    final duration = widget.state.duration.inMilliseconds;
    final position = widget.state.position.inMilliseconds.clamp(0, duration > 0 ? duration : 0);
    return Column(children: [
      if (duration > 0) Slider(key: const Key('vod-seek'), activeColor: const Color(0xFF2196F3), min: 0, max: duration.toDouble(), value: (_scrub ?? position.toDouble()).clamp(0, duration.toDouble()),
        onChanged: (v) => setState(() => _scrub = v), onChangeEnd: (v) { widget.onSeek(Duration(milliseconds: v.round())); setState(() => _scrub = null); _arm(); }),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(mediaTime(widget.state.position), style: const TextStyle(fontSize: 12, color: Colors.white54)),
        Text(duration > 0 ? mediaTime(widget.state.duration) : 'Süre bilgisi yok', style: const TextStyle(fontSize: 12, color: Colors.white54))]),
    ]);
  }
  Widget _action(IconData icon, String label, VoidCallback action, bool compact) => Padding(padding: const EdgeInsets.only(right: 8),
    child: SizedBox(width: compact ? 116 : 148, child: Material(color: const Color(0xEE293A43), borderRadius: BorderRadius.circular(5),
      child: InkWell(borderRadius: BorderRadius.circular(5), focusColor: const Color(0xFF4A626D), onTap: () { _setVisible(false); action(); },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: compact ? 28 : 38), const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12))])))));
}
