String playbackDate(DateTime now) {
  const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  return '${now.day} ${months[now.month - 1]} ${days[now.weekday - 1]} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

List<String> technicalBadges({int? width, int? height, double? fps, int? audioChannels}) {
  final result = <String>[];
  if (width != null && height != null && width > 0 && height > 0) {
    final short = width < height ? width : height;
    result.add(short >= 2160 ? '4K' : short >= 1080 ? 'FULL HD' : short >= 720 ? 'HD' : 'SD');
    result.add('$width × $height');
  }
  if (fps != null && fps.isFinite && fps > 0 && fps <= 240) {
    result.add('${fps.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} FPS');
  }
  if (audioChannels != null && audioChannels > 0) {
    result.add(audioChannels == 1 ? 'MONO' : audioChannels == 2 ? 'STEREO' : '$audioChannels KANAL SES');
  }
  return result;
}

String mediaTime(Duration time) {
  final seconds = time.inSeconds < 0 ? 0 : time.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$remainder' : '$minutes:$remainder';
}
