/// Fora da web não há notificação de navegador (o app nativo usaria outro caminho).
bool webPushSupported() => false;
bool webPushStandalone() => false;
String webPushPermission() => 'denied';
Future<String> webPushRequestPermission() async => 'denied';
Future<String?> webPushSubscribe(String publicKey) async => null;
Future<String?> webPushCurrent() async => null;
Future<String?> webPushUnsubscribe() async => null;
String webUserAgent() => '';

/// Largura da tela (px CSS), idioma, modo escuro e toque; fora da web não há o que medir.
({int width, String lang, bool dark, bool touch}) webDeviceProbe() => (width: 0, lang: '', dark: false, touch: false);
