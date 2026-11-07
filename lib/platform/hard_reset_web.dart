import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Desregistra o service worker, apaga os caches e os dados do site e recarrega,
/// para o usuário receber a versão mais nova mesmo se a página ficou "presa".
Future<void> clearWebCachesAndReload() async {
  const js = '''
(async () => {
  try { for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister(); } catch (e) {}
  try { for (const k of await caches.keys()) await caches.delete(k); } catch (e) {}
  try { localStorage.clear(); sessionStorage.clear(); } catch (e) {}
  location.reload();
})()
''';
  globalContext.callMethod<JSAny?>('eval'.toJS, js.toJS);
}

/// Busca a versão mais nova do site SEM apagar os dados do usuário: remove o
/// service worker e os caches e recarrega com um parâmetro novo na URL (assim
/// o app instalado no celular não fica preso na versão antiga).
Future<bool> updateWebAppAndReload() async {
  const js = '''
(async () => {
  try { for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister(); } catch (e) {}
  try { for (const k of await caches.keys()) await caches.delete(k); } catch (e) {}
  const u = new URL(location.href);
  u.searchParams.set('v', Date.now().toString(36));
  location.replace(u.toString());
})()
''';
  globalContext.callMethod<JSAny?>('eval'.toJS, js.toJS);
  return true;
}
