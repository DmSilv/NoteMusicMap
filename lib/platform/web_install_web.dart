import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_vibrate_web.dart' show webIsIos;

String get _ua {
  final nav = globalContext.getProperty<JSObject?>('navigator'.toJS);
  return nav?.getProperty<JSString?>('userAgent'.toJS)?.toDart ?? '';
}

/// O app já está aberto "como app instalado" (tela cheia, sem barra do navegador)?
bool webIsStandalone() {
  try {
    final mm = globalContext.callMethod<JSObject>('matchMedia'.toJS, '(display-mode: standalone)'.toJS);
    if (mm.getProperty<JSBoolean?>('matches'.toJS)?.toDart == true) return true;
  } catch (_) {}
  // iPhone/iPad (Safari): navigator.standalone.
  final nav = globalContext.getProperty<JSObject?>('navigator'.toJS);
  return nav?.getProperty<JSBoolean?>('standalone'.toJS)?.toDart == true;
}

bool webIsAndroidBrowser() => RegExp('Android', caseSensitive: false).hasMatch(_ua);

/// Navegador de celular ou tablet.
bool webIsMobileBrowser() => webIsAndroidBrowser() || webIsIos() || RegExp('Mobile', caseSensitive: false).hasMatch(_ua);

/// O navegador já avisou que dá para instalar (Chrome/Edge): o botão pode abrir a janela de instalação.
bool webCanPromptInstall() => globalContext.getProperty<JSAny?>('__nmInstall'.toJS) != null;

/// Abre a janela de instalação do navegador. true se a pessoa aceitou.
Future<bool> webPromptInstall() async {
  final ev = globalContext.getProperty<JSObject?>('__nmInstall'.toJS);
  if (ev == null) return false;
  try {
    ev.callMethod<JSAny?>('prompt'.toJS);
    final choice = await ev.getProperty<JSPromise<JSObject>>('userChoice'.toJS).toDart;
    globalContext.setProperty('__nmInstall'.toJS, null); // o aviso só vale uma vez
    return choice.getProperty<JSString?>('outcome'.toJS)?.toDart == 'accepted';
  } catch (_) {
    return false;
  }
}

/// Avisa quando o navegador libera a instalação ou quando o app é instalado.
void webOnInstallEvents(void Function() onChange) {
  final cb = ((JSAny _) => onChange()).toJS;
  globalContext.callMethod<JSAny?>('addEventListener'.toJS, 'nm-install-ready'.toJS, cb);
  globalContext.callMethod<JSAny?>('addEventListener'.toJS, 'nm-installed'.toJS, cb);
}
