import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// O app é só em português do Brasil: os textos do próprio Flutter (seletor de data e hora,
/// "OK"/"Cancelar", copiar/colar, nomes de mês e dia) seguem o mesmo idioma.
/// Custo conhecido: o Flutter embute os textos de todos os idiomas, ~140 KB a mais (compactado) no download do app web.
const kAppLocale = Locale('pt', 'BR');
const kSupportedLocales = [kAppLocale];
const kLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
