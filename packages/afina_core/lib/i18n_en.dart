/// Dicionário português → inglês. A chave é o texto em português exatamente como está em `tr('...')` no código.
/// Marcadores `{0}`, `{1}`… recebem os valores. As traduções ficam em partes (`i18n_en_*.dart`) e são juntadas aqui;
/// `node scripts/check_i18n.js --write` atualiza esta lista quando entra uma parte nova.
library;

import 'i18n_en_a.dart';
import 'i18n_en_b00.dart';
import 'i18n_en_b01.dart';
import 'i18n_en_b02.dart';
import 'i18n_en_b03.dart';
import 'i18n_en_b04.dart';
import 'i18n_en_b05.dart';
import 'i18n_en_b06.dart';
import 'i18n_en_b07.dart';
import 'i18n_en_b08.dart';
import 'i18n_en_b09.dart';
import 'i18n_en_b10.dart';
import 'i18n_en_b11.dart';
import 'i18n_en_b12.dart';
import 'i18n_en_srv.dart';

const Map<String, String> kEn = {
  ...kEnA,
  ...kEnB00,
  ...kEnB01,
  ...kEnB02,
  ...kEnB03,
  ...kEnB04,
  ...kEnB05,
  ...kEnB06,
  ...kEnB07,
  ...kEnB08,
  ...kEnB09,
  ...kEnB10,
  ...kEnB11,
  ...kEnB12,
  ...kEnSrv,
};
