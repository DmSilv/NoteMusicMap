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

/// Fuso horário pelo deslocamento em minutos: "m3" (UTC-3), "p5h" (UTC+5:30), "z" (UTC).
String tzTag(int offsetMinutes) {
  if (offsetMinutes == 0) return 'z';
  final sign = offsetMinutes < 0 ? 'm' : 'p';
  final a = offsetMinutes.abs();
  final h = a ~/ 60, min = a % 60;
  return '$sign$h${min == 0 ? '' : 'h'}';
}

/// Memória aproximada do aparelho em GB (navigator.deviceMemory): "2", "4", "8"… ou "-".
String memTag(num? gb) {
  if (gb == null || gb <= 0) return '-';
  if (gb >= 8) return '8';
  if (gb >= 4) return '4';
  if (gb >= 2) return '2';
  return '1';
}

/// Núcleos do processador em faixas: "c2" (até 2), "c4", "c8", "c12" (mais de 8).
String cpuTag(int? cores) {
  if (cores == null || cores <= 0) return '-';
  if (cores <= 2) return 'c2';
  if (cores <= 4) return 'c4';
  if (cores <= 8) return 'c8';
  return 'c12';
}

/// Qualidade da conexão (navigator.connection.effectiveType): "4g", "3g", "2g", "slow2g" ou "-".
String netTag(String t) => {'4g', '3g', '2g', 'slow-2g'}.contains(t) ? t.replaceAll('-', '') : '-';

/// Densidade de pixels da tela em faixas: "d1", "d2", "d3" (3 ou mais) ou "-".
String dprTag(double? dpr) {
  if (dpr == null || dpr <= 0) return '-';
  if (dpr < 1.5) return 'd1';
  if (dpr < 2.5) return 'd2';
  return 'd3';
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
