import 'dart:typed_data';

/// 把 16kHz 单声道 PCM WAV 裁到最多 [maxSeconds] 秒（上传前用，控制体积）。
/// 解析 RIFF 块找到 fmt/data，重写一个标准 44 字节头。格式不认识时返回 null。
Uint8List? trimWav(Uint8List bytes, {int maxSeconds = 30}) {
  if (bytes.length < 44) return null;
  final bd = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  int? rate, channels, bits, dataOff, dataLen;
  var o = 12;
  while (o + 8 <= bytes.length) {
    final id = tag(o);
    var len = bd.getUint32(o + 4, Endian.little);
    final body = o + 8;
    if (id == 'fmt ') {
      channels = bd.getUint16(body + 2, Endian.little);
      rate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOff = body;
      // 录音中断时头里的长度可能是 0 或超长，以实际字节为准
      if (len == 0 || body + len > bytes.length) len = bytes.length - body;
      dataLen = len;
      break;
    }
    o = body + len + (len.isOdd ? 1 : 0);
  }
  if (rate == null || channels == null || bits == null || dataOff == null || dataLen == null) return null;
  final blockAlign = channels * bits ~/ 8;
  final maxLen = rate * blockAlign * maxSeconds;
  var n = dataLen > maxLen ? maxLen : dataLen;
  n -= n % blockAlign;
  final out = Uint8List(44 + n);
  final w = ByteData.sublistView(out);
  void put(int off, String s) => out.setRange(off, off + 4, s.codeUnits);
  put(0, 'RIFF');
  w.setUint32(4, 36 + n, Endian.little);
  put(8, 'WAVE');
  put(12, 'fmt ');
  w.setUint32(16, 16, Endian.little);
  w.setUint16(20, 1, Endian.little);
  w.setUint16(22, channels, Endian.little);
  w.setUint32(24, rate, Endian.little);
  w.setUint32(28, rate * blockAlign, Endian.little);
  w.setUint16(32, blockAlign, Endian.little);
  w.setUint16(34, bits, Endian.little);
  put(36, 'data');
  w.setUint32(40, n, Endian.little);
  out.setRange(44, 44 + n, bytes, dataOff);
  return out;
}
