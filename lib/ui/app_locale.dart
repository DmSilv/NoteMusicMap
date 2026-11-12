import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:afina_core/afina_core.dart' show AppLang;

/// O app fala português do Brasil ou inglês: os textos do próprio Flutter (seletor de data e hora,
/// "OK"/"Cancelar", copiar/colar, nomes de mês e dia) seguem o idioma escolhido (veja `Lang` e `tr()` em afina_core).
/// Custo conhecido: o Flutter embute os textos de todos os idiomas, ~140 KB a mais (compactado) no download do app web.
const kAppLocale = Locale('pt', 'BR');
const kEnglishLocale = Locale('en');
const kSupportedLocales = [kAppLocale, kEnglishLocale];

/// Locale do Flutter para o idioma do app.
Locale localeFor(AppLang l) => l == AppLang.en ? kEnglishLocale : kAppLocale;
const kLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
