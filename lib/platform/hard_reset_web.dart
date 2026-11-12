import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Atenção: nada de `eval` aqui. A política de segurança do site (CSP) proíbe avaliar texto como código
// e isso fazia "Atualizar o app" e "Apagar tudo" falharem. As rotinas ficam em web/index.html
// (window.nmHardReset e window.nmUpdateApp) e o Dart só as chama.

/// Desregistra o service worker, apaga os caches e os dados do site e recarrega,
/// para o usuário receber a versão mais nova mesmo se a página ficou "presa".
Future<void> clearWebCachesAndReload() async {
  globalContext.callMethod<JSAny?>('nmHardReset'.toJS);
}

/// Recarrega a página: o app começa de novo (usado ao trocar o idioma, para todos os textos nascerem no idioma novo).
/// Devolve true quando pediu o recarregamento.
bool reloadWebPage() {
  try {
    globalContext.getProperty<JSObject>('location'.toJS).callMethod<JSAny?>('reload'.toJS);
    return true;
  } catch (_) {
    return false;
  }
}

/// Busca a versão mais nova do site SEM apagar os dados do usuário: remove o
/// service worker e os caches e recarrega com um parâmetro novo na URL (assim
/// o app instalado no celular não fica preso na versão antiga).
Future<bool> updateWebAppAndReload() async {
  globalContext.callMethod<JSAny?>('nmUpdateApp'.toJS);
  return true;
}
