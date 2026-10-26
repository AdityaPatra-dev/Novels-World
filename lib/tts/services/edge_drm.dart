import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Pure Dart implementation of Microsoft Edge TTS v2 DRM Token Generator
/// (Sec-MS-GEC v2).
///
/// Ports the reference Python v2 token generator with 100% mathematical fidelity.
/// Eliminates 403 Forbidden handshake failures on Microsoft Speech WebSocket API.
class EdgeDrm {
  static const int winEpoch = 11644473600;
  static const double sToNs = 1e9;
  static const String trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String chromiumFullVersion = '143.0.3650.75';
  static const String secMsGecVersion = '2-$chromiumFullVersion';

  static const int _u32Mask = 0xFFFFFFFF;
  static final BigInt _bigMask = BigInt.from(_u32Mask);

  static double _clockSkewSeconds = 0.0;

  static const List<int> _sha256Initial = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ];

  static const List<int> _sha256State = [
    0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
    0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
  ];

  static const List<int> _sha256Schedule = [
    0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA,
    0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6,
    0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
    0xD258B060, 0x72766564,
  ];

  static const List<int> _sha256RoundConstants = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
    0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
    0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
    0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
    0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
    0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
  ];

  static const int _sha256Adjustment = 0xC9DC06A7;
  static final List<int> _sha256BlockConstants = [
    ..._sha256RoundConstants.sublist(0, 14),
    _sha256Adjustment,
    ..._sha256RoundConstants.sublist(15),
  ];

  static const int _sha256Sigma0Adjustment = 0x059C0B80;
  static const int _sha256Sigma1Adjustment = 0x000B92C0;

  static const List<List<int>> _cs64Coefficients = [
    [0xE82E91B1, 0xB32700D0],
    [0x44DE24C6, 0x88DFF51D],
    [0x3BEB65BC, 0x29514038],
    [0xC89C5933, 0xB328CBDF],
    [0x8D1EC211, 0xD405B4D5],
    [0x314EF5D5, 0x26E55F3C],
    [0xE92491B1, 0x607801C6],
    [0xF0A5B9D5, 0x82B2C1FB],
    [0x06064CF3, 0xFA51A3DA],
    [0xDA79FA60, 0x207CC464],
    [0xBED20560, 0x3C3C74F3],
    [0x89F9C9F8, 0xD2D14B61],
    [0x35FA38C6, 0xBB04A2C1],
    [0xCB49E3C6, 0xC5626167],
  ];

  static const int _cs64Factor = 0x82893933;
  static const int _cs64Adjustment0 = 0xF2F90B1A;
  static const int _cs64Adjustment1 = 0x0B1A0000;

  static void updateClockSkew(String serverDate) {
    try {
      final serverTime = HttpDate.parse(serverDate);
      final localTime = DateTime.now().toUtc();
      _clockSkewSeconds = serverTime.difference(localTime).inMilliseconds / 1000.0;
    } catch (_) {}
  }

  static double get unixTimestamp {
    return (DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0) + _clockSkewSeconds;
  }

  static int _rol16(int value) {
    final v = value & _u32Mask;
    return (((v << 16) & _u32Mask) | (v >> 16)) & _u32Mask;
  }

  static List<int> _wordsLe4Even(Uint8List data) {
    final padLen = (-data.length) % 4;
    final padded = Uint8List(data.length + padLen);
    padded.setAll(0, data);
    if (padded.isEmpty) return [];

    final byteData = ByteData.sublistView(padded);
    final count = padded.length ~/ 4;
    final words = <int>[];
    for (int i = 0; i < count; i++) {
      words.add(byteData.getUint32(i * 4, Endian.little));
    }
    if (words.length % 2 != 0) {
      words.add(0);
    }
    return words;
  }

  static int _sigma0(int value) {
    final v = value & _u32Mask;
    return ((v >> 7) ^
            ((v << 25) & _u32Mask) ^
            (v >> 18) ^
            ((v << 14) & _u32Mask) ^
            (v >> 3)) &
        _u32Mask;
  }

  static int _sigma1(int value) {
    final v = value & _u32Mask;
    return ((v >> 17) ^
            ((v << 15) & _u32Mask) ^
            (v >> 19) ^
            ((v << 13) & _u32Mask) ^
            (v >> 10)) &
        _u32Mask;
  }

  static List<int> _sha256Rounds(List<int> state, List<int> words, {int firstRound = 0}) {
    int a = state[0], b = state[1], c = state[2], d = state[3];
    int e = state[4], f = state[5], g = state[6], h = state[7];
    final mask = _u32Mask;
    final constants = firstRound == 14 ? _sha256BlockConstants : _sha256RoundConstants;

    final aligned = min(64, ((firstRound + 7) ~/ 8) * 8);
    for (int index = firstRound; index < aligned; index++) {
      final rotE = BigInt.from(e & mask) * BigInt.from(0x100000001);
      final rotA = BigInt.from(a & mask) * BigInt.from(0x100000001);

      final t1 = (h +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (g ^ (e & (f ^ g))) +
              constants[index] +
              words[index]) &
          mask;
      final t2 = (((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((a & b) | (c & (a | b)))) &
          mask;

      h = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }

    for (int index = aligned; index < 64; index += 8) {
      // 0
      var rotE = BigInt.from(e & mask) * BigInt.from(0x100000001);
      var rotA = BigInt.from(a & mask) * BigInt.from(0x100000001);
      var t1 = (h +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (g ^ (e & (f ^ g))) +
              constants[index] +
              words[index]) &
          mask;
      d = (d + t1) & mask;
      h = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((a & b) | (c & (a | b)))) &
          mask;

      // 1
      rotE = BigInt.from(d & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(h & mask) * BigInt.from(0x100000001);
      t1 = (g +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (f ^ (d & (e ^ f))) +
              constants[index + 1] +
              words[index + 1]) &
          mask;
      c = (c + t1) & mask;
      g = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((h & a) | (b & (h | a)))) &
          mask;

      // 2
      rotE = BigInt.from(c & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(g & mask) * BigInt.from(0x100000001);
      t1 = (f +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (e ^ (c & (d ^ e))) +
              constants[index + 2] +
              words[index + 2]) &
          mask;
      b = (b + t1) & mask;
      f = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((g & h) | (a & (g | h)))) &
          mask;

      // 3
      rotE = BigInt.from(b & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(f & mask) * BigInt.from(0x100000001);
      t1 = (e +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (d ^ (b & (c ^ d))) +
              constants[index + 3] +
              words[index + 3]) &
          mask;
      a = (a + t1) & mask;
      e = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((f & g) | (h & (f | g)))) &
          mask;

      // 4
      rotE = BigInt.from(a & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(e & mask) * BigInt.from(0x100000001);
      t1 = (d +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (c ^ (a & (b ^ c))) +
              constants[index + 4] +
              words[index + 4]) &
          mask;
      h = (h + t1) & mask;
      d = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((e & f) | (g & (e | f)))) &
          mask;

      // 5
      rotE = BigInt.from(h & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(d & mask) * BigInt.from(0x100000001);
      t1 = (c +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (b ^ (h & (a ^ b))) +
              constants[index + 5] +
              words[index + 5]) &
          mask;
      g = (g + t1) & mask;
      c = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((d & e) | (f & (d | e)))) &
          mask;

      // 6
      rotE = BigInt.from(g & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(c & mask) * BigInt.from(0x100000001);
      t1 = (b +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (a ^ (g & (h ^ a))) +
              constants[index + 6] +
              words[index + 6]) &
          mask;
      f = (f + t1) & mask;
      b = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((c & d) | (e & (c | d)))) &
          mask;

      // 7
      rotE = BigInt.from(f & mask) * BigInt.from(0x100000001);
      rotA = BigInt.from(b & mask) * BigInt.from(0x100000001);
      t1 = (a +
              ((rotE >> 6).toInt() ^ (rotE >> 11).toInt() ^ (rotE >> 25).toInt()) +
              (h ^ (f & (g ^ h))) +
              constants[index + 7] +
              words[index + 7]) &
          mask;
      e = (e + t1) & mask;
      a = (t1 +
              ((rotA >> 2).toInt() ^ (rotA >> 13).toInt() ^ (rotA >> 22).toInt()) +
              ((b & c) | (d & (b | c)))) &
          mask;
    }

    return [a, b, c, d, e, f, g, h];
  }

  static void _expandSha256Schedule(List<int> words, {int firstWord = 16}) {
    final mask = _u32Mask;
    for (int index = firstWord; index < 64; index++) {
      final x = words[index - 2];
      final y = words[index - 15];
      final sigma1 = _sigma1(x);
      final sigma0 = _sigma0(y);
      words.add((sigma1 + words[index - 7] + sigma0 + words[index - 16]) & mask);
    }
  }

  static List<int> _sha256Init(Uint8List data) {
    final mask = _u32Mask;
    final words = List<int>.filled(14, 0, growable: true);
    int b0 = (data[0] << 16) | (data[1] << 8) | data[2];
    words.add(b0);
    int b1 = (data[3] << 24) | (data[4] << 16) | (data[5] << 8) | data[6];
    words.add(b1);

    for (int index = 16; index < 30; index++) {
      int value = _sha256Schedule[index - 16];
      if (index - 2 >= 14) {
        value += index == 16
            ? (_sigma1(words[index - 2]) ^ _sha256Sigma1Adjustment)
            : _sigma1(words[index - 2]);
      }
      if (index - 7 >= 14) {
        value += words[index - 7];
      }
      if (index - 15 >= 14) {
        value += index == 29
            ? (_sigma0(words[index - 15]) ^ _sha256Sigma0Adjustment)
            : _sigma0(words[index - 15]);
      }
      words.add(value & mask);
    }

    words.add((_sigma1(words[28]) +
            words[23] +
            _sigma0(words[15]) +
            words[14] +
            _sha256Adjustment -
            _sha256RoundConstants[14]) &
        mask);

    _expandSha256Schedule(words, firstWord: 31);
    final working = _sha256Rounds(_sha256State, words, firstRound: 14);
    return List<int>.generate(8, (i) => (_sha256Initial[i] + working[i]) & mask);
  }

  static Uint8List _sha256Digest(Uint8List data) {
    if (data.length < 7) {
      throw ArgumentError('Token salt must contain at least seven bytes');
    }
    final mask = _u32Mask;
    final length = 57 + data.length;
    final rem = (55 - length) % 64;
    final padLen = rem < 0 ? rem + 64 : rem;
    final padded = Uint8List(data.length - 7 + 1 + padLen + 8);
    padded.setRange(0, data.length - 7, data.sublist(7));
    padded[data.length - 7] = 0x80;
    final bitLen = BigInt.from(length) * BigInt.from(8);
    for (int i = 0; i < 8; i++) {
      padded[padded.length - 1 - i] = ((bitLen >> (i * 8)) & BigInt.from(0xFF)).toInt();
    }

    var state = _sha256Init(data.sublist(0, 7));
    final byteData = ByteData.sublistView(padded);
    for (int offset = 0; offset < padded.length; offset += 64) {
      final words = <int>[];
      for (int i = 0; i < 16; i++) {
        words.add(byteData.getUint32(offset + i * 4, Endian.big));
      }
      _expandSha256Schedule(words);
      final working = _sha256Rounds(state, words);
      state = List<int>.generate(8, (i) => (state[i] + working[i]) & mask);
    }

    final out = Uint8List(32);
    final outData = ByteData.sublistView(out);
    for (int i = 0; i < 8; i++) {
      outData.setUint32(i * 4, state[i], Endian.big);
    }
    return out;
  }

  static List<int> _cs64Digest(Uint8List data, Uint8List digest) {
    final mask = _u32Mask;
    final digestData = ByteData.sublistView(digest);
    int keyA = digestData.getUint32(0, Endian.little) | 1;
    int keyB = digestData.getUint32(4, Endian.little) | 1;

    final factors = [
      ((BigInt.from(keyA) * BigInt.from(_cs64Factor)) & _bigMask).toInt(),
      ((BigInt.from(keyB) * BigInt.from(_cs64Factor)) & _bigMask).toInt(),
    ];

    final terms = <int>[];
    for (int i = 0; i < _cs64Coefficients.length; i++) {
      final coef = _cs64Coefficients[i][0];
      terms.add(((BigInt.from(coef) * BigInt.from(factors[i % 2])) & _bigMask).toInt());
    }
    final offsets = [for (final c in _cs64Coefficients) c[1]];

    final zeroPrepended = Uint8List(data.length + 1);
    zeroPrepended[0] = 0;
    zeroPrepended.setRange(1, zeroPrepended.length, data);
    final words = _wordsLe4Even(zeroPrepended);

    for (int index = 0; index < words.length; index++) {
      final word = words[index];
      int term = ((BigInt.from(word) * BigInt.from(index % 2 == 0 ? keyA : keyB)) & _bigMask).toInt();
      int offset = ((BigInt.from(_rol16(word)) * BigInt.from(index % 2 == 0 ? 0xEF0569FB : 0xC31713DB)) & _bigMask).toInt();
      if (index == 0) {
        term = (term + ((BigInt.from(_cs64Adjustment0) * BigInt.from(factors[0])) & _bigMask).toInt()) & mask;
        offset = (offset + _cs64Adjustment1) & mask;
      }
      terms.add(term & mask);
      offsets.add(offset & mask);
    }

    int swapAcc = 0, swapLast = 0, state = 0, acc = 0;
    for (int index = 0; index < terms.length; index += 2) {
      final x = terms[index], y = terms[index + 1];
      var t = _rol16((offsets[index] + x) & mask);
      var q = ((BigInt.from(t) * BigInt.from(0x76F50F34)) & _bigMask).toInt();
      swapAcc = (swapAcc + (((BigInt.from(_rol16(q)) * BigInt.from(0xC3EFEA97)) & _bigMask).toInt()) + q) & mask;

      t = _rol16((offsets[index + 1] + y) & mask);
      q = ((BigInt.from(t) * BigInt.from(0x1881CE3C)) & _bigMask).toInt();
      swapLast = (((BigInt.from(_rol16(q)) * BigInt.from(0x35BD1EC9)) & _bigMask).toInt()) + q;
      swapLast &= mask;
      swapAcc = (swapAcc + swapLast) & mask;

      state = ((BigInt.from(state) * BigInt.from(keyA) + BigInt.from(x)) & _bigMask).toInt();
      state = ((BigInt.from(_rol16(state)) * BigInt.from(0xCF98B111)) & _bigMask).toInt();
      state = ((BigInt.from(_rol16(state)) * BigInt.from(0x87085B9F)) & _bigMask).toInt();
      state = ((BigInt.from(_rol16(state)) * BigInt.from(0x12CEB96D)) & _bigMask).toInt();
      state = ((BigInt.from(_rol16(state)) * BigInt.from(0x257E1D83)) & _bigMask).toInt();
      acc = (acc + state) & mask;

      t = ((BigInt.from(state) * BigInt.from(keyB) + BigInt.from(y)) & _bigMask).toInt();
      t = ((BigInt.from(_rol16(t)) * BigInt.from(0xA27416F5)) & _bigMask).toInt();
      t = ((BigInt.from(_rol16(t)) * BigInt.from(0xD38396FF)) & _bigMask).toInt();
      state = (((BigInt.from(_rol16((_rol16(t) * 0x7C932B89) & mask)) * BigInt.from(0xBFA49F69)) & _bigMask)).toInt();
      acc = (acc + state) & mask;
    }

    return [(swapLast ^ state) & mask, (swapAcc ^ acc) & mask];
  }

  static String _toHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  /// Generates the v2 Sec-MS-GEC token format: `<16 hex CS64>-<64 hex SHA256>`
  static String generateSecMsGecV2([double? timestamp]) {
    double ticks = timestamp ?? unixTimestamp;
    ticks += winEpoch;
    ticks -= ticks % 300;
    ticks *= sToNs / 100;
    final strToHash = '${ticks.toStringAsFixed(0)}$trustedClientToken';
    final data = Uint8List.fromList(ascii.encode(strToHash));

    final digest = _sha256Digest(data);
    final cs64Words = _cs64Digest(data, digest);

    final cs64Bytes = Uint8List(8);
    final bd = ByteData.sublistView(cs64Bytes);
    bd.setUint32(0, cs64Words[0], Endian.little);
    bd.setUint32(4, cs64Words[1], Endian.little);

    final cs64Hex = _toHex(cs64Bytes);
    final sha256Hex = _toHex(digest);
    return '$cs64Hex-$sha256Hex';
  }

  static String generateMuid() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16))
        .join()
        .toUpperCase();
  }

  static String generateUuidHex() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  static String generateTimestamp() {
    final now = DateTime.now().toUtc();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final wd = weekdays[now.weekday - 1];
    final mo = months[now.month - 1];
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');

    return '$wd $mo $d ${now.year} $h:$mi:$s GMT+0000 (Coordinated Universal Time)';
  }
}

