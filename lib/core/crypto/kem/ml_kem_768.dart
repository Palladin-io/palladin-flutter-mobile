import 'dart:typed_data';

import 'package:pointycastle/digests/sha3.dart';
import 'package:pointycastle/digests/shake.dart';

/// FIPS 203 ML-KEM-768, used only as the lattice half of X-Wing.
///
/// Arithmetic on secret coefficients avoids data-dependent branches and
/// hardware division (KyberSlash): reductions use multiply-shift constants and
/// the decapsulation re-encryption check selects the result with a mask.
abstract final class MlKem768 {
  static const encapsulationKeyBytes = 1184;
  static const decapsulationKeyBytes = 2400;
  static const ciphertextBytes = 1088;
  static const sharedSecretBytes = 32;

  /// `ML-KEM.KeyGen_internal(d, z)`; returns `(ek, dk)`.
  static (Uint8List, Uint8List) keyGenInternal(Uint8List d, Uint8List z) {
    if (d.length != 32 || z.length != 32) {
      throw ArgumentError('ML-KEM seed length');
    }
    final g = _sha3_512(
      _concat([
        d,
        Uint8List.fromList([_k]),
      ]),
    );
    final rho = Uint8List.sublistView(g, 0, 32);
    final sigma = Uint8List.sublistView(g, 32, 64);
    final matrix = _generateMatrix(rho);
    var counter = 0;
    final s = [for (var i = 0; i < _k; i++) _cbd2(_prf(sigma, counter++))];
    final e = [for (var i = 0; i < _k; i++) _cbd2(_prf(sigma, counter++))];
    s.forEach(_ntt);
    e.forEach(_ntt);
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < _k; i++) {
      final t = Int32List(_n);
      for (var j = 0; j < _k; j++) {
        _addInto(t, _multiplyNtts(matrix[i][j], s[j]));
      }
      _addInto(t, e[i]);
      builder.add(_encode12(t));
    }
    builder.add(rho);
    final ek = builder.takeBytes();
    final dkBuilder = BytesBuilder(copy: false);
    for (final poly in s) {
      dkBuilder.add(_encode12(poly));
    }
    dkBuilder
      ..add(ek)
      ..add(_sha3_256(ek))
      ..add(z);
    for (final poly in [...s, ...e]) {
      poly.fillRange(0, _n, 0);
    }
    g.fillRange(0, g.length, 0);
    return (ek, dkBuilder.takeBytes());
  }

  /// `ML-KEM.Encaps_internal(ek, m)`; returns `(sharedSecret, ciphertext)`.
  static (Uint8List, Uint8List) encapsulateInternal(Uint8List ek, Uint8List m) {
    if (ek.length != encapsulationKeyBytes || m.length != 32) {
      throw ArgumentError('ML-KEM encapsulation input length');
    }
    _checkEncapsulationKey(ek);
    final g = _sha3_512(_concat([m, _sha3_256(ek)]));
    try {
      final key = Uint8List.fromList(g.sublist(0, 32));
      final ciphertext = _encrypt(ek, m, Uint8List.sublistView(g, 32, 64));
      return (key, ciphertext);
    } finally {
      g.fillRange(0, g.length, 0);
    }
  }

  /// `ML-KEM.Decaps_internal(dk, c)` with implicit rejection.
  static Uint8List decapsulate(Uint8List dk, Uint8List c) {
    if (dk.length != decapsulationKeyBytes || c.length != ciphertextBytes) {
      throw ArgumentError('ML-KEM decapsulation input length');
    }
    final dkPke = Uint8List.sublistView(dk, 0, 384 * _k);
    final ek = Uint8List.sublistView(dk, 384 * _k, 768 * _k + 32);
    final h = Uint8List.sublistView(dk, 768 * _k + 32, 768 * _k + 64);
    final z = Uint8List.sublistView(dk, 768 * _k + 64, 768 * _k + 96);
    final m = _decrypt(dkPke, c);
    final g = _sha3_512(_concat([m, h]));
    final rejection = _shake256(_concat([z, c]), 32);
    final reencrypted = _encrypt(ek, m, Uint8List.sublistView(g, 32, 64));
    try {
      var difference = 0;
      for (var i = 0; i < ciphertextBytes; i++) {
        difference |= c[i] ^ reencrypted[i];
      }
      // mask = 0xff when equal, 0x00 otherwise, without branching on secrets.
      final mask = ((difference - 1) >> 8) & 0xff;
      final out = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        out[i] = (g[i] & mask) | (rejection[i] & ~mask & 0xff);
      }
      return out;
    } finally {
      m.fillRange(0, m.length, 0);
      g.fillRange(0, g.length, 0);
      rejection.fillRange(0, rejection.length, 0);
      reencrypted.fillRange(0, reencrypted.length, 0);
    }
  }
}

const _n = 256;
const _q = 3329;
const _k = 3;
const _du = 10;
const _dv = 4;

final List<int> _zetas = _powers(odd: false);
final List<int> _gammas = _powers(odd: true);

List<int> _powers({required bool odd}) {
  int bitRev7(int value) {
    var out = 0;
    for (var bit = 0; bit < 7; bit++) {
      out |= ((value >> bit) & 1) << (6 - bit);
    }
    return out;
  }

  int pow17(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result = (result * 17) % _q;
    }
    return result;
  }

  return [
    for (var i = 0; i < 128; i++) pow17(odd ? 2 * bitRev7(i) + 1 : bitRev7(i)),
  ];
}

/// Barrett reduction for `0 <= a < 2^32` without hardware division.
int _reduce(int a) {
  final quotient = (a * 1290167) >> 32;
  var r = a - quotient * _q;
  r -= _q;
  r += (r >> 63) & _q;
  return r;
}

void _ntt(Int32List f) {
  var i = 1;
  for (var len = 128; len >= 2; len >>= 1) {
    for (var start = 0; start < _n; start += 2 * len) {
      final zeta = _zetas[i++];
      for (var j = start; j < start + len; j++) {
        final t = _reduce(zeta * f[j + len]);
        f[j + len] = _reduce(f[j] - t + _q);
        f[j] = _reduce(f[j] + t);
      }
    }
  }
}

void _inverseNtt(Int32List f) {
  var i = 127;
  for (var len = 2; len <= 128; len <<= 1) {
    for (var start = 0; start < _n; start += 2 * len) {
      final zeta = _zetas[i--];
      for (var j = start; j < start + len; j++) {
        final t = f[j];
        f[j] = _reduce(t + f[j + len]);
        f[j + len] = _reduce(zeta * (f[j + len] - t + _q));
      }
    }
  }
  for (var j = 0; j < _n; j++) {
    f[j] = _reduce(f[j] * 3303);
  }
}

Int32List _multiplyNtts(Int32List f, Int32List g) {
  final h = Int32List(_n);
  for (var i = 0; i < 128; i++) {
    final a0 = f[2 * i], a1 = f[2 * i + 1];
    final b0 = g[2 * i], b1 = g[2 * i + 1];
    h[2 * i] = _reduce(a0 * b0 + _reduce(_reduce(a1 * b1) * _gammas[i]));
    h[2 * i + 1] = _reduce(a0 * b1 + a1 * b0);
  }
  return h;
}

void _addInto(Int32List target, Int32List other) {
  for (var i = 0; i < _n; i++) {
    target[i] = _reduce(target[i] + other[i]);
  }
}

List<List<Int32List>> _generateMatrix(Uint8List rho) => [
  for (var i = 0; i < _k; i++)
    [for (var j = 0; j < _k; j++) _sampleNtt(rho, j, i)],
];

/// Rejection sampling over public `rho`; its timing reveals nothing secret.
Int32List _sampleNtt(Uint8List rho, int j, int i) {
  final xof = SHAKEDigest(128)
    ..update(rho, 0, rho.length)
    ..updateByte(j)
    ..updateByte(i);
  final out = Int32List(_n);
  final block = Uint8List(168);
  var count = 0;
  while (count < _n) {
    xof.doOutput(block, 0, block.length);
    for (var offset = 0; offset < block.length && count < _n; offset += 3) {
      final d1 = block[offset] | ((block[offset + 1] & 0x0f) << 8);
      final d2 = (block[offset + 1] >> 4) | (block[offset + 2] << 4);
      if (d1 < _q) out[count++] = d1;
      if (d2 < _q && count < _n) out[count++] = d2;
    }
  }
  return out;
}

Uint8List _prf(Uint8List seed, int counter) => _shake256(
  _concat([
    seed,
    Uint8List.fromList([counter]),
  ]),
  128,
);

/// `SamplePolyCBD_2` from 128 PRF bytes.
Int32List _cbd2(Uint8List bytes) {
  final out = Int32List(_n);
  for (var i = 0; i < _n; i++) {
    final nibble = (bytes[i >> 1] >> ((i & 1) * 4)) & 0x0f;
    final x = (nibble & 1) + ((nibble >> 1) & 1);
    final y = ((nibble >> 2) & 1) + ((nibble >> 3) & 1);
    var value = x - y;
    value += (value >> 63) & _q;
    out[i] = value;
  }
  bytes.fillRange(0, bytes.length, 0);
  return out;
}

/// `round(2^d * x / q) mod 2^d` via a 2^-40 multiply-shift (exact for x < q).
int _compress(int x, int d) =>
    ((((x << (d + 1)) + _q) * 165141429) >> 40) & ((1 << d) - 1);

int _decompress(int y, int d) => (_q * y + (1 << (d - 1))) >> d;

Uint8List _encodeBits(Int32List f, int d) {
  final out = Uint8List(32 * d);
  for (var i = 0; i < _n; i++) {
    final value = f[i];
    for (var bit = 0; bit < d; bit++) {
      final index = i * d + bit;
      out[index >> 3] |= ((value >> bit) & 1) << (index & 7);
    }
  }
  return out;
}

Int32List _decodeBits(Uint8List bytes, int offset, int d) {
  final out = Int32List(_n);
  for (var i = 0; i < _n; i++) {
    var value = 0;
    for (var bit = 0; bit < d; bit++) {
      final index = i * d + bit;
      value |= ((bytes[offset + (index >> 3)] >> (index & 7)) & 1) << bit;
    }
    out[i] = value;
  }
  return out;
}

Uint8List _encode12(Int32List f) {
  final out = Uint8List(384);
  for (var i = 0; i < 128; i++) {
    final a = f[2 * i], b = f[2 * i + 1];
    out[3 * i] = a & 0xff;
    out[3 * i + 1] = (a >> 8) | ((b & 0x0f) << 4);
    out[3 * i + 2] = b >> 4;
  }
  return out;
}

Int32List _decode12(Uint8List bytes, int offset) {
  final out = Int32List(_n);
  for (var i = 0; i < 128; i++) {
    final b0 = bytes[offset + 3 * i];
    final b1 = bytes[offset + 3 * i + 1];
    final b2 = bytes[offset + 3 * i + 2];
    out[2 * i] = b0 | ((b1 & 0x0f) << 8);
    out[2 * i + 1] = (b1 >> 4) | (b2 << 4);
  }
  return out;
}

/// FIPS 203 encapsulation-key modulus check.
void _checkEncapsulationKey(Uint8List ek) {
  for (var i = 0; i < _k; i++) {
    final poly = _decode12(ek, 384 * i);
    for (final coefficient in poly) {
      if (coefficient >= _q) throw ArgumentError('ML-KEM encapsulation key');
    }
  }
}

Uint8List _encrypt(Uint8List ek, Uint8List m, Uint8List r) {
  final t = [for (var i = 0; i < _k; i++) _decode12(ek, 384 * i)];
  final matrix = _generateMatrix(Uint8List.sublistView(ek, 384 * _k));
  var counter = 0;
  final y = [for (var i = 0; i < _k; i++) _cbd2(_prf(r, counter++))];
  final e1 = [for (var i = 0; i < _k; i++) _cbd2(_prf(r, counter++))];
  final e2 = _cbd2(_prf(r, counter++));
  y.forEach(_ntt);
  final builder = BytesBuilder(copy: false);
  for (var i = 0; i < _k; i++) {
    final u = Int32List(_n);
    for (var j = 0; j < _k; j++) {
      _addInto(u, _multiplyNtts(matrix[j][i], y[j]));
    }
    _inverseNtt(u);
    _addInto(u, e1[i]);
    for (var c = 0; c < _n; c++) {
      u[c] = _compress(u[c], _du);
    }
    builder.add(_encodeBits(u, _du));
  }
  final v = Int32List(_n);
  for (var i = 0; i < _k; i++) {
    _addInto(v, _multiplyNtts(t[i], y[i]));
  }
  _inverseNtt(v);
  _addInto(v, e2);
  final mu = _decodeBits(m, 0, 1);
  for (var c = 0; c < _n; c++) {
    v[c] = _compress(_reduce(v[c] + _decompress(mu[c], 1)), _dv);
  }
  builder.add(_encodeBits(v, _dv));
  for (final poly in [...y, ...e1, e2, mu, v]) {
    poly.fillRange(0, _n, 0);
  }
  return builder.takeBytes();
}

Uint8List _decrypt(Uint8List dkPke, Uint8List c) {
  final w = Int32List(_n);
  for (var i = 0; i < _k; i++) {
    final u = _decodeBits(c, 320 * i, _du);
    for (var j = 0; j < _n; j++) {
      u[j] = _decompress(u[j], _du);
    }
    _ntt(u);
    final s = _decode12(dkPke, 384 * i);
    for (var j = 0; j < _n; j++) {
      s[j] = _reduce(s[j]);
    }
    _addInto(w, _multiplyNtts(s, u));
    s.fillRange(0, _n, 0);
  }
  _inverseNtt(w);
  final v = _decodeBits(c, 320 * _k, _dv);
  for (var j = 0; j < _n; j++) {
    w[j] = _compress(_reduce(_decompress(v[j], _dv) - w[j] + _q), 1);
  }
  final m = _encodeBits(w, 1);
  w.fillRange(0, _n, 0);
  return m;
}

Uint8List _sha3_256(Uint8List input) => _digest(SHA3Digest(256), input, 32);

Uint8List _sha3_512(Uint8List input) => _digest(SHA3Digest(512), input, 64);

Uint8List _shake256(Uint8List input, int length) {
  final digest = SHAKEDigest(256)..update(input, 0, input.length);
  final out = Uint8List(length);
  digest.doFinalRange(out, 0, length);
  return out;
}

Uint8List _digest(SHA3Digest digest, Uint8List input, int length) {
  digest.update(input, 0, input.length);
  final out = Uint8List(length);
  digest.doFinal(out, 0);
  return out;
}

Uint8List _concat(List<Uint8List> parts) {
  final builder = BytesBuilder(copy: false);
  parts.forEach(builder.add);
  return builder.takeBytes();
}

/// Exposed only so tests can exhaustively check the division-free helpers.
int debugCompress(int x, int d) => _compress(x, d);

/// Exposed only so tests can exhaustively check the division-free helpers.
int debugReduce(int a) => _reduce(a);
