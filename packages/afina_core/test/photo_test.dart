import 'dart:convert';
import 'dart:typed_data';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

// Cabeçalhos mínimos mas verdadeiros (o núcleo lê largura e altura deles).
Uint8List jpeg([int n = 100, int w = 160, int h = 160]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, h >> 8, h & 255, w >> 8, w & 255, 0x03, ...List.filled(n, 7)]);
Uint8List png([int w = 96, int h = 96]) {
  final b = ByteData(33);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(8, 13);
  for (var i = 0; i < 4; i++) {
    b.setUint8(12 + i, 'IHDR'.codeUnitAt(i));
  }
  b.setUint32(16, w);
  b.setUint32(20, h);
  return b.buffer.asUint8List();
}

Uint8List webp(String kind, int w, int h) {
  final b = Uint8List(40);
  b.setRange(0, 4, 'RIFF'.codeUnits);
  b.setRange(8, 12, 'WEBP'.codeUnits);
  b.setRange(12, 16, kind.codeUnits);
  if (kind == 'VP8X') {
    b[24] = (w - 1) & 255; b[25] = ((w - 1) >> 8) & 255; b[26] = ((w - 1) >> 16) & 255;
    b[27] = (h - 1) & 255; b[28] = ((h - 1) >> 8) & 255; b[29] = ((h - 1) >> 16) & 255;
  } else if (kind == 'VP8 ') {
    b[26] = w & 255; b[27] = (w >> 8) & 0x3F; b[28] = h & 255; b[29] = (h >> 8) & 0x3F;
  } else {
    b[20] = 0x2F;
    final bits = (w - 1) | ((h - 1) << 14);
    b[21] = bits & 255; b[22] = (bits >> 8) & 255; b[23] = (bits >> 16) & 255; b[24] = (bits >> 24) & 255;
  }
  return b;
}

void main() {
  group('foto de pessoa', () {
    test('reconhece JPEG, PNG e WebP pelos primeiros bytes', () {
      expect(sniffImage(jpeg()), 'jpeg');
      expect(sniffImage(png()), 'png');
      expect(sniffImage(webp('VP8X', 10, 10)), 'webp');
      expect(sniffImage(Uint8List.fromList([0x3C, 0x73, 0x76, 0x67])), isNull, reason: 'SVG/HTML não entra');
      expect(sniffImage(Uint8List(0)), isNull);
    });

    test('aceita base64 de imagem pequena, com ou sem prefixo data: e espaços', () {
      final b64 = base64Encode(jpeg());
      expect(cleanPhoto(b64), b64);
      expect(cleanPhoto('data:image/jpeg;base64,$b64'), b64);
      expect(cleanPhoto('  ${b64.substring(0, 8)}\n${b64.substring(8)} '), b64);
    });

    test('recusa o que não é imagem, é grande demais ou não é base64', () {
      expect(cleanPhoto(null), isNull);
      expect(cleanPhoto(''), isNull);
      expect(cleanPhoto('isto não é base64!!'), isNull);
      expect(cleanPhoto(base64Encode(utf8.encode('<script>alert(1)</script>'))), isNull);
      expect(cleanPhoto(base64Encode(jpeg(kMaxPhotoBytes))), isNull, reason: 'passou do limite');
      expect(cleanPhoto('A' * 60000), isNull);
    });

    test('no limite exato ainda passa', () {
      final ok = jpeg(kMaxPhotoBytes - 12);
      expect(ok.length, kMaxPhotoBytes);
      expect(cleanPhoto(base64Encode(ok)), isNotNull);
    });

    test('lê as dimensões do cabeçalho e recusa o que declara pixels demais (bomba de descompressão)', () {
      expect(imageSize(png(96, 80)), (96, 80));
      expect(imageSize(jpeg(10, 160, 120)), (160, 120));
      for (final k in ['VP8X', 'VP8 ', 'VP8L']) {
        expect(imageSize(webp(k, 200, 150)), (200, 150), reason: k);
      }
      expect(cleanPhoto(base64Encode(png(512, 512))), isNotNull);
      for (final bomb in [png(20000, 20000), jpeg(50, 30000, 30000), webp('VP8X', 16000, 16000), webp('VP8L', 9000, 9000), png(513, 100), png(0, 0)]) {
        expect(cleanPhoto(base64Encode(bomb)), isNull);
      }
      expect(imageSize(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])), isNull, reason: 'sem cabeçalho de tamanho');
    });

    test('photoBytes devolve os bytes e a marca muda com o conteúdo', () {
      final a = base64Encode(jpeg(50)), b = base64Encode(jpeg(51));
      expect(photoBytes(a), jpeg(50));
      expect(photoBytes('lixo'), isNull);
      expect(photoTag(a), isNot(photoTag(b)));
      expect(photoTag(a), photoTag(a));
      expect(photoTag(a).length, greaterThanOrEqualTo(7));
    });
  });

  group('foto do aluno na ficha', () {
    test('vai e volta pelo JSON do aluno', () {
      final b64 = base64Encode(jpeg());
      final s = Student(id: 's', name: 'Ana', photo: b64);
      final back = Student.tryFrom(s.toJson())!;
      expect(back.photo, b64);
    });

    test('sem foto, o JSON não ganha campo novo', () {
      expect(Student(id: 's', name: 'Ana').toJson().containsKey('ph'), isFalse);
    });

    test('foto estragada no JSON é descartada e o aluno continua', () {
      final j = Student(id: 's', name: 'Ana').toJson()..['ph'] = 'lixo';
      final back = Student.tryFrom(j)!;
      expect(back.name, 'Ana');
      expect(back.photo, isNull);
    });

    test('exportar os dados do aluno não leva a foto', () {
      final s = Student(id: 's', name: 'Ana', photo: base64Encode(jpeg()));
      expect(exportStudent(s).contains('"ph"'), isFalse);
      expect(importStudent(exportStudent(s))!.photo, isNull);
    });
  });
}
