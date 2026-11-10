/// Rótulos curtos e ANÔNIMOS de aparelho para as estatísticas do painel.
///
/// Só categorias (nunca o texto cru do navegador): cada rótulo tem até 10 letras ou
/// números minúsculos, o que permite combinar filtros sem identificar ninguém.
library;

/// Faixa de largura da tela (pixels CSS): celular, tablet ou pc. "-" = desconhecido.
String screenTag(int width) {
  if (width <= 0) return '-';
  if (width < 600) return 'celular';
  if (width < 1024) return 'tablet';
  return 'pc';
}

/// Idioma do navegador reduzido às línguas que importam; o resto vira "outro".
String langTag(String lang) {
  final l = lang.trim().toLowerCase();
  if (l.length < 2) return '-';
  final base = l.substring(0, 2);
  const known = {'pt', 'en', 'es', 'fr', 'de', 'it'};
  return known.contains(base) ? base : 'outro';
}

/// Versão principal do sistema: "a13" (Android 13), "i17" (iOS 17), "w10" (Windows 10/11),
/// "wold" (Windows antigo). Mac e Linux não dão versão confiável: "-".
String osVersionTag(String ua) {
  final a = RegExp(r'Android (\d{1,2})').firstMatch(ua);
  if (a != null) return 'a${a.group(1)}';
  if (RegExp('iPhone|iPad|iPod').hasMatch(ua)) {
    final i = RegExp(r'OS (\d{1,2})[_.]').firstMatch(ua);
    return i != null ? 'i${i.group(1)}' : '-';
  }
  final w = RegExp(r'Windows NT (\d+)').firstMatch(ua);
  if (w != null) return w.group(1) == '10' ? 'w10' : 'wold';
  return '-';
}

/// "sim", "nao" ou "nd" (não definido) para estados de permissão e opções.
String yesNoTag(bool? v) => v == null ? 'nd' : (v ? 'sim' : 'nao');

/// Permissão de notificação do navegador ("granted", "denied", "default") em rótulo curto.
String notifTag(bool supported, String permission) {
  if (!supported) return 'na';
  return switch (permission) {
    'granted' => 'sim',
    'denied' => 'nao',
    _ => 'nd',
  };
}
