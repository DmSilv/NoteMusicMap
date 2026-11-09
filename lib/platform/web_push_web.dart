import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Ponte para `window.nmPush` (definida em web/index.html). Tudo protegido: se algo faltar ou o
/// navegador recusar, devolve "sem suporte" em vez de lançar erro.
JSObject? get _nm => globalContext.getProperty<JSObject?>('nmPush'.toJS);

bool webPushSupported() {
  try {
    final nm = _nm;
    if (nm == null) return false;
    return nm.callMethod<JSBoolean?>('supported'.toJS)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// O site está instalado na tela inicial (obrigatório para receber notificação no iPhone).
bool webPushStandalone() {
  try {
    return _nm?.callMethod<JSBoolean?>('standalone'.toJS)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// 'granted', 'denied' ou 'default' (ainda não perguntou).
String webPushPermission() {
  try {
    return _nm?.callMethod<JSString?>('permission'.toJS)?.toDart ?? 'denied';
  } catch (_) {
    return 'denied';
  }
}

/// Pede permissão (precisa vir de um toque da pessoa).
Future<String> webPushRequestPermission() async {
  try {
    final p = _nm?.callMethod<JSPromise<JSString>?>('request'.toJS);
    if (p == null) return 'denied';
    return (await p.toDart).toDart;
  } catch (_) {
    return 'denied';
  }
}

/// Inscreve este aparelho (com a chave pública do servidor). Devolve o JSON da inscrição.
Future<String?> webPushSubscribe(String publicKey) async {
  try {
    final p = _nm?.callMethod<JSPromise<JSString>?>('subscribe'.toJS, publicKey.toJS);
    if (p == null) return null;
    return (await p.toDart).toDart;
  } catch (_) {
    return null;
  }
}

/// A inscrição atual deste aparelho (JSON) ou vazio se não há.
Future<String?> webPushCurrent() async {
  try {
    final p = _nm?.callMethod<JSPromise<JSString>?>('current'.toJS);
    if (p == null) return null;
    final s = (await p.toDart).toDart;
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

/// Cancela a inscrição deste aparelho. Devolve o endereço que foi cancelado (ou null).
Future<String?> webPushUnsubscribe() async {
  try {
    final p = _nm?.callMethod<JSPromise<JSString>?>('unsubscribe'.toJS);
    if (p == null) return null;
    final s = (await p.toDart).toDart;
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

/// O texto que o navegador diz ser (para separar Android/iPhone/computador e o navegador).
String webUserAgent() {
  try {
    final nav = globalContext.getProperty<JSObject?>('navigator'.toJS);
    return nav?.getProperty<JSString?>('userAgent'.toJS)?.toDart ?? '';
  } catch (_) {
    return '';
  }
}
