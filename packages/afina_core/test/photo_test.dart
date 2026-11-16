import 'dart:convert';
import 'dart:typed_data';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

Uint8List jpeg([int n = 100]) => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(n, 7)]);
Uint8List png([int n = 100]) => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(n, 3)]);
Uint8List webp() => Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50, 9, 9]);

void main() {
  group('foto de pessoa', () {
    test('reconhece JPEG, PNG e WebP pelos primeiros bytes', () {
      expect(sniffImage(jpeg()), 'jpeg');
      expect(sniffImage(png()), 'png');
      expect(sniffImage(webp()), 'webp');
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
      final ok = jpeg(kMaxPhotoBytes - 4);
      expect(ok.length, kMaxPhotoBytes);
      expect(cleanPhoto(base64Encode(ok)), isNotNull);
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
