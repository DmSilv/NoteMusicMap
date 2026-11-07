{{flutter_js}}
{{flutter_build_config}}

// Sem o service worker do Flutter (nesta versão ele só se desregistra). O app usa o
// próprio `sw.js`, registrado no index.html, para funcionar sem internet e poder ser instalado.
_flutter.loader.load();
