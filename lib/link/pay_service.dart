import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/coach_ai.dart' show kApiBase;

/// Resposta do plano Pro (Pix) de `/api/account`: `plan`, `pay_new` e `pay_check`.
class PayReply {
  final bool ok;
  final bool offline;

  /// O servidor está com o Pix desligado (PAY_ENABLED) ou sem as chaves.
  final bool off;

  /// `plan`: o Pix está ligado no servidor e este perfil pode comprar o plano de teste.
  final bool enabled;
  final bool test;

  /// Plano atual: se é Pro, até quando (ms desde 1970) e quantos dias faltam.
  final bool pro;
  final int until;
  final int daysLeft;

  /// `pay_new`: o pagamento (id), o "copia e cola", a imagem do QR (base64 de PNG), o valor e a validade.
  final String id;
  final String qr;
  final String qrBase64;
  final double amount;
  final String expires;

  /// `pay_check`: pending, approved, rejected, cancelled...
  final String status;
  final String error;
  const PayReply({
    this.ok = false,
    this.offline = false,
    this.off = false,
    this.enabled = false,
    this.test = false,
    this.pro = false,
    this.until = 0,
    this.daysLeft = 0,
    this.id = '',
    this.qr = '',
    this.qrBase64 = '',
    this.amount = 0,
    this.expires = '',
    this.status = '',
    this.error = '',
  });
}

/// Fala com `/api/account` para o plano Pro por Pix. Só o código e o segredo do aparelho vão ao servidor, nunca dados de pagamento.
class PayService {
  PayService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/account');
    if (kIsWeb) return Uri.base.resolve('/api/account');
    return null;
  }

  Future<PayReply> _post(Map<String, dynamic> body) async {
    final ep = _endpoint();
    if (ep == null) return const PayReply(offline: true);
    try {
      final r = await _http.post(ep, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      Map<String, dynamic> j = {};
      try {
        j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      } catch (_) {}
      if (r.statusCode == 503) return PayReply(off: true, error: (j['error'] as String?) ?? '');
      if (r.statusCode != 200) return PayReply(error: (j['error'] as String?) ?? 'http_${r.statusCode}');
      return PayReply(
        ok: true,
        enabled: j['enabled'] == true,
        test: j['test'] == true,
        pro: j['pro'] == true,
        until: (j['until'] as num?)?.toInt() ?? 0,
        daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
        id: (j['id'] as String?) ?? '',
        qr: (j['qr'] as String?) ?? '',
        qrBase64: (j['qrBase64'] as String?) ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        expires: (j['expires'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
      );
    } catch (_) {
      return const PayReply(offline: true);
    }
  }

  Future<PayReply> plan(String code, String secret) => _post({'code': code, 'secret': secret, 'action': 'plan'});

  /// [period]: 'm' mensal, 'y' anual, 't' teste (R$ 1, só para perfis liberados no servidor).
  Future<PayReply> payNew(String code, String secret, String period) => _post({'code': code, 'secret': secret, 'action': 'pay_new', 'period': period});

  Future<PayReply> payCheck(String code, String secret, String id) => _post({'code': code, 'secret': secret, 'action': 'pay_check', 'id': id});

  void dispose() => _http.close();
}
