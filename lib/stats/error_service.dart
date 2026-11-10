import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/coach_ai.dart' show kApiBase;

/// Envia um relatório de erro (anônimo e já higienizado) para o servidor. Falha em silêncio:
/// relatar um erro nunca pode causar outro. Em teste local (localhost) não envia.
class ErrorReportService {
  static Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/errors');
    if (kIsWeb) {
      final h = Uri.base.host;
      if (h == 'localhost' || h == '127.0.0.1' || h.isEmpty) return null;
      return Uri.base.resolve('/api/errors');
    }
    return null;
  }

  /// Código aleatório descartável, para quando o app nem conseguiu abrir (sem preferências).
  static String tempId() {
    final r = math.Random.secure();
    const a = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(24, (_) => a[r.nextInt(a.length)]).join();
  }

  /// true = o servidor aceitou (ou está desligado de propósito).
  static Future<bool> send(Map<String, dynamic> report, {http.Client? client}) async {
    final ep = _endpoint();
    if (ep == null) return false;
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(ep, headers: {'Content-Type': 'application/json'}, body: jsonEncode(report))
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (client == null) c.close();
    }
  }
}
