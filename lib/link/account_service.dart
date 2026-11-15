import 'dart:async';
import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/coach_ai.dart' show kApiBase;

/// Resposta de uma chamada ao e-mail da conta.
class AccountReply {
  final bool ok;

  /// O servidor ou o envio de e-mail não está disponível (ainda não configurado): o app esconde o recurso.
  final bool unavailable;

  /// Sem internet ou servidor com problema: tentar de novo depois.
  final bool offline;

  /// Esse e-mail já protege outra conta.
  final bool inUse;

  /// Pediu códigos demais.
  final bool tooMany;

  /// Código errado, vencido ou já usado.
  final bool badCode;

  /// E-mail ou pedido recusado de vez.
  final bool rejected;

  /// Status: o recurso está ligado no servidor, este perfil tem e-mail e a versão mascarada dele.
  final bool enabled;
  final bool linked;
  final String hint;

  /// Chave de 25: o servidor tem uma deste perfil (status) e a chave recém-gerada (rk_new).
  final bool hasKey;
  final String key;

  /// Entrar com e-mail: o código do perfil e o apelido que voltam do servidor.
  final String code;
  final String name;
  const AccountReply({
    this.ok = false,
    this.unavailable = false,
    this.offline = false,
    this.inUse = false,
    this.tooMany = false,
    this.badCode = false,
    this.rejected = false,
    this.enabled = false,
    this.linked = false,
    this.hint = '',
    this.hasKey = false,
    this.key = '',
    this.code = '',
    this.name = '',
  });
}

/// Fala com `/api/account`: e-mail da conta, sem senha. Só o e-mail digitado e os códigos de 6 dígitos passam por aqui.
class AccountService {
  AccountService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/account');
    if (kIsWeb) return Uri.base.resolve('/api/account');
    return null;
  }

  Future<AccountReply> _post(Map<String, dynamic> body) async {
    final ep = _endpoint();
    if (ep == null) return const AccountReply(unavailable: true);
    try {
      final r = await _http.post(ep, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
      Map<String, dynamic> j = {};
      try {
        j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      } catch (_) {}
      if (r.statusCode == 503 || r.statusCode == 404) return const AccountReply(unavailable: true);
      if (r.statusCode == 409) return const AccountReply(inUse: true, rejected: true);
      if (r.statusCode == 429) return const AccountReply(tooMany: true);
      if (r.statusCode == 403) return const AccountReply(badCode: true, rejected: true);
      if (r.statusCode >= 500 || r.statusCode == 502) return const AccountReply(offline: true);
      if (r.statusCode != 200) return const AccountReply(rejected: true);
      return AccountReply(
        ok: true,
        enabled: j['enabled'] == true,
        linked: j['linked'] == true,
        hint: cleanText(j['hint'] as String?, max: 80),
        hasKey: j['hasKey'] == true,
        key: normalizeShortKey((j['key'] as String?) ?? '') ?? '',
        code: formatShareCode((j['code'] as String?) ?? '') ?? '',
        name: cleanText(j['name'] as String?, max: kMaxName),
      );
    } catch (_) {
      return const AccountReply(offline: true);
    }
  }

  Map<String, dynamic> _auth(String code, String secret) => {'code': code, 'secret': secret};
  static String get _lang => Lang.isEn ? 'en' : 'pt';

  Future<AccountReply> status(String code, String secret) => _post({..._auth(code, secret), 'action': 'status'});

  Future<AccountReply> bindStart(String code, String secret, String email) =>
      _post({..._auth(code, secret), 'action': 'bind_start', 'email': email, 'lang': _lang});

  Future<AccountReply> bindVerify(String code, String secret, String email, String otp) =>
      _post({..._auth(code, secret), 'action': 'bind_verify', 'email': email, 'otp': otp});

  Future<AccountReply> unbind(String code, String secret) => _post({..._auth(code, secret), 'action': 'unbind'});

  Future<AccountReply> loginStart(String email) => _post({'action': 'login_start', 'email': email, 'lang': _lang});

  /// Gera a chave de recuperação de 25 caracteres (a anterior deixa de valer).
  Future<AccountReply> keyNew(String code, String secret) => _post({..._auth(code, secret), 'action': 'rk_new'});

  /// Aparelho novo: entra com a chave de 25 e passa a ser o dono do perfil.
  Future<AccountReply> keyLogin(String key, String secret) => _post({'action': 'rk_login', 'key': key, 'secret': secret});

  Future<AccountReply> loginVerify(String email, String otp, String secret) => _post({'action': 'login_verify', 'email': email, 'otp': otp, 'secret': secret});

  void dispose() => _http.close();
}
