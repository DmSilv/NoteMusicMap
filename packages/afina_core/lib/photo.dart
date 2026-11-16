/// Foto pequena de pessoa (o próprio perfil ou um aluno): guardada como texto base64 de uma imagem JPEG, PNG ou WebP
/// já reduzida pelo app. Aqui só se confere e se limpa o que entra (da galeria, do servidor, de um backup): é um texto
/// que vira imagem na tela, então nada fora de uma imagem pequena e bem formada passa. Dart puro e testável.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Tamanho máximo da imagem já reduzida (bytes). Uma foto de 160 px em JPEG fica em 4 a 12 mil.
const int kMaxPhotoBytes = 24000;

/// Como o app reduz a foto ao escolher: lado maior em pixels e qualidade do JPEG (dá de 4 a 12 mil bytes).
const int kPhotoSide = 160;
const int kPhotoQuality = 60;

/// Formato da imagem pelos primeiros bytes: 'jpeg', 'png', 'webp' ou null se não for nenhum deles.
String? sniffImage(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) return 'png';
  if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
  return null;
}

/// A foto como texto base64 limpo (sem prefixo "data:" nem espaços), ou null se não for uma imagem aceita e pequena.
String? cleanPhoto(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty || s.length > (kMaxPhotoBytes * 4 ~/ 3) + 16) return null;
  final comma = s.indexOf(',');
  if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1);
  s = s.replaceAll(RegExp(r'\s'), '');
  try {
    final bytes = base64Decode(base64.normalize(s));
    if (bytes.isEmpty || bytes.length > kMaxPhotoBytes) return null;
    if (sniffImage(bytes) == null) return null;
    return base64Encode(bytes);
  } catch (_) {
    return null;
  }
}

/// Os bytes de uma foto já limpa, ou null.
Uint8List? photoBytes(String? clean) {
  final c = cleanPhoto(clean);
  if (c == null) return null;
  try {
    return base64Decode(c);
  } catch (_) {
    return null;
  }
}

/// Identificador curto da foto (muda quando a foto muda): 8 símbolos do conteúdo, para comparar versões sem baixar a imagem.
String photoTag(String clean) {
  var h = 0x811C9DC5; // FNV-1a de 32 bits
  for (final c in clean.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(36).padLeft(7, '0');
}
