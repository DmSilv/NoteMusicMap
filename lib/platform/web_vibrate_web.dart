import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Vibração na web: o plugin `vibration` só funciona em Android/iOS nativos, então
/// aqui chamamos `navigator.vibrate` direto. Funciona no Chrome, Edge e Firefox do
/// Android (depois de a pessoa tocar na tela uma vez). O iPhone/iPad não oferece
/// essa API a sites, e computadores não têm motor de vibração.
JSObject? get _nav => globalContext.getProperty<JSObject?>('navigator'.toJS);

String get _userAgent {
  final nav = _nav;
  if (nav == null) return '';
  return nav.getProperty<JSString?>('userAgent'.toJS)?.toDart ?? '';
}

/// iPhone, iPad e iPod (inclui o iPad que se apresenta como Mac).
bool webIsIos() {
  final ua = _userAgent;
  if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return true;
  final nav = _nav;
  final touches = nav?.getProperty<JSNumber?>('maxTouchPoints'.toJS)?.toDartInt ?? 0;
  return ua.contains('Macintosh') && touches > 1;
}

/// O navegador tem `navigator.vibrate` E é de celular/tablet (no computador a
/// função existe em alguns navegadores, mas não faz nada: não vale anunciar).
bool webVibrationSupported() {
  final nav = _nav;
  if (nav == null || webIsIos()) return false;
  if (!nav.hasProperty('vibrate'.toJS).toDart) return false;
  return RegExp(r'Android|Mobile|Tablet', caseSensitive: false).hasMatch(_userAgent);
}

/// Vibra segundo [pattern] (ms: vibra, espera, vibra…). Devolve false se o navegador recusar.
bool webVibrate(List<int> pattern) {
  try {
    final nav = _nav;
    if (nav == null) return false;
    final arg = pattern.map((e) => e.toJS).toList().toJS;
    return nav.callMethod<JSBoolean?>('vibrate'.toJS, arg)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
