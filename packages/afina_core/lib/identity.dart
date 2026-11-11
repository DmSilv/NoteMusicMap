/// Identidade do perfil (Fase 1): quem é a pessoa, sem cadastro e sem servidor.
///
/// - [Profile.id]: UUID do perfil. Todos os dados pertencem a ele, não ao aparelho.
/// - [Profile.secret]: 256 bits aleatórios que provam que você é o dono. Nunca é
///   mostrado nem enviado por acaso; só entra na chave de recuperação.
/// - [Profile.shareCode]: código curto e legível ("K7QM-4TXD") para ser achado
///   por um professor. Sozinho NÃO dá acesso a nada.
/// - Chave de recuperação: texto (ou QR) que recria o mesmo perfil em outro
///   aparelho ou depois de reinstalar.
///
/// Dart puro e testável. O sorteio vem de fora ([Random]); no app usa-se
/// `Random.secure()`. Tudo evita deslocamentos de bits (a web só tem 32 bits).
library;

import 'dart:math';

import 'input_guard.dart';

/// 32 símbolos sem 0, O, 1 e I (não se confundem ao ler ou digitar).
const String kCodeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

const int _payloadLen = 7; // + 1 de verificação = 8 caracteres

String _hex(Random r, int bytes) {
  final b = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// UUID versão 4 ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx").
String newUuid(Random r) {
  final h = _hex(r, 16).split('');
  h[12] = '4';
  h[16] = '89ab'[r.nextInt(4)];
  final s = h.join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

final RegExp _uuidRe =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

bool isUuid(String s) => _uuidRe.hasMatch(s);

int _checkIndex(String payload) {
  var sum = 0;
  for (var i = 0; i < payload.length; i++) {
    final v = kCodeAlphabet.indexOf(payload[i]);
    // Pesos ímpares (1, 3, 5…) são inversíveis mod 32: qualquer caractere
    // errado muda a soma, e a troca de vizinhos quase sempre também.
    sum += v * (2 * i + 1);
  }
  return sum % kCodeAlphabet.length;
}

/// Código de identificação: 7 símbolos sorteados + 1 de verificação,
/// escrito "XXXX-XXXX".
String newShareCode(Random r) {
  final b = StringBuffer();
  for (var i = 0; i < _payloadLen; i++) {
    b.write(kCodeAlphabet[r.nextInt(kCodeAlphabet.length)]);
  }
  final p = b.toString();
  final full = p + kCodeAlphabet[_checkIndex(p)];
  return '${full.substring(0, 4)}-${full.substring(4)}';
}

/// Tira espaços e hífens e põe em maiúsculas. Devolve "" se sobrar algo fora do alfabeto.
String normalizeShareCode(String input) {
  final s = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  for (final c in s.split('')) {
    if (!kCodeAlphabet.contains(c)) return '';
  }
  return s;
}

/// O código digitado é bem formado (tamanho, alfabeto e verificação)?
bool isValidShareCode(String input) {
  final s = normalizeShareCode(input);
  if (s.length != _payloadLen + 1) return false;
  return kCodeAlphabet[_checkIndex(s.substring(0, _payloadLen))] == s[_payloadLen];
}

/// "K7QM4TXD" ou "k7qm-4txd" → "K7QM-4TXD"; null se inválido.
String? formatShareCode(String input) {
  if (!isValidShareCode(input)) return null;
  final s = normalizeShareCode(input);
  return '${s.substring(0, 4)}-${s.substring(4)}';
}

/// O que um QR ou link lido contém: o [code] (já formatado) e de quem é.
class ScannedCode {
  final String code;

  /// 'aluno' (QR do aluno), 'professor' (QR do professor) ou 'codigo' (só o código).
  final String kind;
  const ScannedCode(this.code, this.kind);
}

/// Endereços cujos links o app aceita ler (o do próprio app). Qualquer outro
/// site é recusado, mesmo que o link traga `?aluno=`.
const Set<String> kAppHosts = {'notemusicmap.vercel.app', 'localhost', '127.0.0.1'};

/// Entende o que a câmera leu (ou o que a pessoa colou): um link DO APP com
/// `?aluno=` ou `?professor=`, `notemusic:CÓDIGO`, ou o próprio código.
///
/// Devolve null (sem abrir nem usar nada) se:
///  - for grande demais ou tiver caracteres de controle/invisíveis;
///  - for um link de outro site, ou de outro tipo (mailto:, tel:, wifi:, contato…);
///  - o código não estiver bem formado (tamanho, alfabeto e dígito de verificação).
/// [extraHosts]: outros endereços válidos (ex.: o domínio de onde o app está rodando).
ScannedCode? parseScannedCode(String raw, {Set<String> extraHosts = const {}}) {
  if (raw.length > kMaxQr) return null;
  final t = raw.trim();
  if (t.isEmpty || hasUnsafeChars(t)) return null;

  if (t.toLowerCase().startsWith('notemusic:')) {
    final c = formatShareCode(t.substring(10));
    return c == null ? null : ScannedCode(c, 'codigo');
  }

  final u = Uri.tryParse(t);
  if (u != null && u.hasScheme) {
    // Link: só http/https e só do endereço do app.
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    final host = u.host.toLowerCase();
    final ok = kAppHosts.contains(host) || extraHosts.map((h) => h.toLowerCase()).contains(host);
    if (!ok) return null;
    for (final k in const ['aluno', 'professor']) {
      final v = u.queryParameters[k];
      final c = v == null ? null : formatShareCode(v);
      if (c != null) return ScannedCode(c, k);
    }
    return null;
  }

  // Sem esquema: tem que ser o próprio código ("K7QM-4TXD").
  final c = formatShareCode(t);
  return c == null ? null : ScannedCode(c, 'codigo');
}

class Profile {
  final String id;
  final String secret; // 64 caracteres hex
  final String shareCode;
  final DateTime created;

  /// Nome opcional (só para você se reconhecer).
  String? name;

  /// Capacidade "professor" (desligada por padrão). Todo mundo é aluno; quem
  /// quiser ensinar liga isto nas configurações. Não existe perfil "de professor"
  /// separado: o mesmo perfil pratica e ensina, sem duplicar telas nem dados.
  bool teacher;

  /// Quando a chave de recuperação foi mostrada/copiada pela última vez.
  DateTime? recoveryShownAt;

  Profile({
    required this.id,
    required this.secret,
    required this.shareCode,
    DateTime? created,
    this.name,
    this.teacher = false,
    this.recoveryShownAt,
  }) : created = created ?? DateTime.now();

  /// Cria um perfil novo.
  factory Profile.create(Random r, {DateTime? now}) => Profile(
        id: newUuid(r),
        secret: _hex(r, 32),
        shareCode: newShareCode(r),
        created: now,
      );

  /// Perfil novo com um código que já existe (liberação pelo suporte): identidade e segredo novos
  /// neste aparelho, o mesmo código de sempre.
  factory Profile.withCode(Random r, String shareCode, {DateTime? now}) => Profile(
        id: newUuid(r),
        secret: _hex(r, 32),
        shareCode: shareCode,
        created: now,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'sec': secret,
        'code': shareCode,
        'c': created.toIso8601String(),
        if (name != null) 'name': name,
        if (teacher) 'teacher': true,
        if (recoveryShownAt != null) 'rec': recoveryShownAt!.toIso8601String(),
      };

  static Profile? tryFrom(Map<String, dynamic> j) {
    try {
      final id = j['id'] as String;
      final sec = j['sec'] as String;
      final code = j['code'] as String;
      if (!isUuid(id) || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sec) || !isValidShareCode(code)) {
        return null;
      }
      return Profile(
        id: id,
        secret: sec,
        shareCode: formatShareCode(code)!,
        created: DateTime.tryParse((j['c'] as String?) ?? ''),
        name: j['name'] as String?,
        teacher: j['teacher'] == true,
        recoveryShownAt: DateTime.tryParse((j['rec'] as String?) ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Chave de recuperação
// ---------------------------------------------------------------------------

const String _keyPrefix = 'NM1';

/// Soma ponderada em 16 bits (detecta erro de digitação; não é criptografia).
String _keyCheck(String body) {
  var a = 0, b = 0;
  for (final c in body.codeUnits) {
    a = (a + c) % 251;
    b = (b + a) % 251;
  }
  return (a * 251 + b).toRadixString(16).padLeft(4, '0');
}

/// Texto que guarda o perfil: `NM1-<id>-<segredo>-<código>-<verificação>`,
/// em grupos fáceis de copiar. Quem tiver este texto pode virar este perfil;
/// por isso o app avisa para guardá-lo em lugar seguro.
String recoveryKeyFor(Profile p) {
  final idHex = p.id.replaceAll('-', '');
  final code = normalizeShareCode(p.shareCode).toLowerCase();
  final body = '$idHex${p.secret}$code';
  final groups = <String>[];
  for (var i = 0; i < body.length; i += 8) {
    groups.add(body.substring(i, i + 8 > body.length ? body.length : i + 8));
  }
  return '$_keyPrefix-${groups.join('-')}-${_keyCheck(body)}';
}

/// Código de suporte (uso único, gerado no painel do administrador): 8 letras/números, com ou sem
/// hífen. Devolve "XXXX-XXXX" ou null se estiver malformado.
String? normalizeSupportCode(String input) {
  final t = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$').hasMatch(t)) return null;
  return '${t.substring(0, 4)}-${t.substring(4)}';
}

/// Lê uma chave de recuperação. Aceita maiúsculas, espaços e quebras de linha.
/// Devolve null se estiver incompleta, com erro de digitação ou de outra versão.
Profile? profileFromRecoveryKey(String text, {DateTime? now}) {
  final raw = text.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
  final parts = raw.split('-');
  if (parts.length < 3 || parts.first != _keyPrefix.toLowerCase()) return null;
  final check = parts.last;
  final body = parts.sublist(1, parts.length - 1).join();
  // 32 (id) + 64 (segredo) hex + 8 do código.
  if (body.length != 32 + 64 + 8) return null;
  if (_keyCheck(body) != check) return null;
  final hexPart = body.substring(0, 96);
  if (!RegExp(r'^[0-9a-f]{96}$').hasMatch(hexPart)) return null;
  final id = '${hexPart.substring(0, 8)}-${hexPart.substring(8, 12)}-${hexPart.substring(12, 16)}-'
      '${hexPart.substring(16, 20)}-${hexPart.substring(20, 32)}';
  final code = formatShareCode(body.substring(96));
  if (!isUuid(id) || code == null) return null;
  return Profile(id: id, secret: hexPart.substring(32), shareCode: code, created: now);
}
