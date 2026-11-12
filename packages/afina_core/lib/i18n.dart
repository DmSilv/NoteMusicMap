/// Idiomas do app (português e inglês) e a função [tr].
///
/// Como funciona: o texto no código é o PORTUGUÊS (`tr('Salvar')`). Com o idioma em português, [tr] devolve o próprio texto;
/// em inglês, procura a tradução em [kEn] (`i18n_en.dart`) e, se não achar, devolve o português (nunca uma tela vazia).
/// Valores que entram no texto vão como argumentos: `tr('{0} foi excluído.', [nome])`, e a tradução usa os mesmos
/// marcadores (`'{0} was deleted.'`), podendo até trocar a ordem. Um teste (`i18n_test.dart` e `scripts/check_i18n.js`) exige que
/// todo texto do código tenha tradução e que os marcadores batam.
library;

import 'i18n_en.dart';

enum AppLang { pt, en }

/// O idioma de hoje. É um valor só para o app inteiro (núcleo e telas).
class Lang {
  Lang._();

  static AppLang current = AppLang.pt;
  static bool get isEn => current == AppLang.en;

  /// Código curto: 'pt' ou 'en'.
  static String get code => current.name;

  /// Idioma a usar para o aparelho com a língua [deviceTag] (ex.: "en-US", "pt-BR", "es"). Inglês só se o aparelho estiver em
  /// inglês; todo o resto fica em português, que é o padrão do app.
  static AppLang forDevice(String? deviceTag) => (deviceTag ?? '').toLowerCase().startsWith('en') ? AppLang.en : AppLang.pt;

  /// Lê 'auto' | 'pt' | 'en' (o que a pessoa escolheu em Ajustes) e devolve o idioma, olhando o aparelho no 'auto'.
  static AppLang resolve(String? pref, String? deviceTag) => switch (pref) {
        'pt' => AppLang.pt,
        'en' => AppLang.en,
        _ => forDevice(deviceTag),
      };
}

final RegExp _slot = RegExp(r'\{(\d+)\}');

/// Troca os marcadores `{0}`, `{1}`… de [text] pelos [args].
String fillSlots(String text, List<Object?> args) {
  if (args.isEmpty) return text;
  return text.replaceAllMapped(_slot, (m) {
    final i = int.parse(m[1]!);
    return i < args.length ? '${args[i]}' : m[0]!;
  });
}

/// Quando o mesmo texto em português tem sentidos diferentes em inglês, acrescente `@@contexto` ao final da chave
/// (`'{0} de {1}@@mês'`): o contexto só distingue as chaves do dicionário e nunca aparece na tela.
String _noCtx(String s) {
  final i = s.indexOf('@@');
  return i < 0 ? s : s.substring(0, i);
}

/// Texto na língua de hoje. [pt] é o texto em português (e a chave do dicionário); [args] preenchem `{0}`, `{1}`…
String tr(String pt, [List<Object?> args = const []]) {
  final base = Lang.isEn ? (kEn[pt] ?? _noCtx(pt)) : _noCtx(pt);
  return fillSlots(base, args);
}

/// Texto que veio de fora (servidor) e talvez já tenha tradução no dicionário: traduz se souber, senão devolve como veio.
String trServer(String? msg) => msg == null || msg.isEmpty ? '' : tr(msg);
