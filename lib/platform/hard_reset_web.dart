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
