import 'dart:async';
import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/coach_ai.dart' show kApiBase;

/// Um aparelho em que a conta está aberta (o servidor nunca manda o segredo dele).
class AccountDevice {
  final String id;

  /// Sistema ("android", "ios", "windows", "mac", "linux"), navegador ("chrome130") e modelo, como o servidor viu.
  final String os;
  final String browser;
  final String model;

  /// Apelido que a pessoa deu ao aparelho (vazio se não deu).
  final String nick;
  final DateTime? created;
  final DateTime? lastSeen;

  /// É o aparelho que está usando o app agora.
  final bool current;
  const AccountDevice({required this.id, this.os = '', this.browser = '', this.model = '', this.nick = '', this.created, this.lastSeen, this.current = false});

  static AccountDevice? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final id = cleanText(m['id'] as String?, max: 16);
      if (id.isEmpty) return null;
      DateTime? at(Object? v) {
        final n = (v as num?)?.toInt() ?? 0;
        return n <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(n.clamp(0, 4102444800000));
      }

      return AccountDevice(
        id: id,
        os: cleanText(m['ou'] as String?, max: 12),
        browser: cleanText(m['br'] as String?, max: 16),
        model: cleanText(m['md'] as String?, max: 32),
        nick: cleanText(m['dn'] as String?, max: 40),
        created: at(m['c']),
        lastSeen: at(m['l']),
        current: m['me'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

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

  /// Código de pareamento recém-gerado (`pair_new`) e quantos segundos ele vale.
  final String pair;
  final int pairTtl;

  /// Aparelhos da conta (resposta de `devices`) e o máximo permitido.
  final List<AccountDevice> devices;
  final int maxDevices;

  /// A conta já está no máximo de aparelhos: [devices] diz quais; a pessoa escolhe qual tirar e repete o pedido.
  final bool limit;
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
    this.devices = const [],
    this.maxDevices = 5,
    this.limit = false,
    this.pair = '',
    this.pairTtl = 0,
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
      if (r.statusCode == 422 && j['error'] == 'device_limit') {
        return AccountReply(limit: true, rejected: true, maxDevices: (j['max'] as num?)?.toInt() ?? 5, devices: _devices(j['devices']));
      }
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
        devices: _devices(j['devices']),
        maxDevices: (j['max'] as num?)?.toInt() ?? 5,
        pair: normalizePairCode((j['pair'] as String?) ?? '') ?? '',
        pairTtl: ((j['ttl'] as num?)?.toInt() ?? 0).clamp(0, 3600),
      );
    } catch (_) {
      return const AccountReply(offline: true);
    }
  }

  static List<AccountDevice> _devices(Object? v) => [for (final x in ((v as List?) ?? const []).take(10)) ?AccountDevice.tryFrom(x)];

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

  /// Aparelho novo: entra com a chave de 25 e passa a ser um dos aparelhos da conta. Com a conta cheia, [drop] é o id do que sai.
  Future<AccountReply> keyLogin(String key, String secret, {String? drop}) =>
      _post({'action': 'rk_login', 'key': key, 'secret': secret, 'drop': ?drop});

  Future<AccountReply> loginVerify(String email, String otp, String secret, {String? drop}) =>
      _post({'action': 'login_verify', 'email': email, 'otp': otp, 'secret': secret, 'drop': ?drop});

  /// Gera um código de 10 minutos para ligar outro aparelho a esta conta.
  Future<AccountReply> pairNew(String code, String secret) => _post({..._auth(code, secret), 'action': 'pair_new'});

  /// Aparelho novo: entra na conta com o código gerado no outro aparelho. Com a conta cheia, [drop] é o id do que sai.
  Future<AccountReply> pairJoin(String pair, String secret, {String? drop}) =>
      _post({'action': 'pair_join', 'pair': pair, 'secret': secret, 'drop': ?drop});

  /// Os aparelhos em que a conta está aberta.
  Future<AccountReply> devices(String code, String secret) => _post({..._auth(code, secret), 'action': 'devices'});

  /// Tira um aparelho da conta (nunca o que está pedindo).
  Future<AccountReply> deviceRemove(String code, String secret, String id) => _post({..._auth(code, secret), 'action': 'device_remove', 'id': id});

  /// Dá um apelido a ESTE aparelho.
  Future<AccountReply> deviceName(String code, String secret, String nick) => _post({..._auth(code, secret), 'action': 'device_name', 'dn': nick});

  void dispose() => _http.close();
}
