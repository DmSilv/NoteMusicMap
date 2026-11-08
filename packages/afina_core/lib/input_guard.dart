/// Limpeza e limites de tudo que a pessoa digita, cola ou lê de um QR. Dart puro.
///
/// O app não monta HTML nem consulta banco com esses textos, mas eles aparecem
/// na tela, vão para backups colados e (em resumo) para a IA. Por isso:
///  - tira caracteres de controle e os que "enganam" a leitura (inversão de
///    sentido da escrita, largura zero, separadores de linha escondidos);
///  - limita o tamanho de cada campo, contando letras e não bytes (sem partir
///    emojis ao meio);
///  - limita o tamanho do que se cola para importar (evita travar o aparelho).
library;

/// Tamanhos máximos (caracteres).
const int kMaxName = 60; // nome de aluno, apelido
const int kMaxTitle = 80; // método, título de tarefa
const int kMaxLine = 160; // uma lição, um detalhe
const int kMaxNote = 500; // observação, comentário
const int kMaxList = 4000; // várias lições digitadas de uma vez
const int kMaxImport = 20000; // texto colado para importar métodos
const int kMaxBackup = 300000; // dados de um aluno colados (JSON)
const int kMaxQr = 300; // o que uma leitura de QR pode ter
const int kMaxMethods = 150; // métodos numa importação
const int kMaxLessons = 400; // lições por método numa importação

// Caracteres que nunca devem aparecer em um texto digitado:
//  U+0000-001F, 007F-009F: controle (menos \n e \t quando o campo é multilinha)
//  U+00AD: hífen invisível
//  U+200B-200F, 202A-202E, 2060-2064, 2066-2069, FEFF: largura zero e direção do texto
//  U+2028-2029: separadores de linha/parágrafo escondidos
//  U+E0000-E007F: "tags" invisíveis
bool _isUnsafe(int c, bool multiline) {
  if (c == 0x0A) return !multiline;
  if (c == 0x09) return false; // tab: vira espaço depois
  if (c <= 0x1F || (c >= 0x7F && c <= 0x9F)) return true;
  if (c == 0xAD) return true;
  if (c >= 0x200B && c <= 0x200F) return true;
  if (c >= 0x2028 && c <= 0x202E) return true;
  if (c >= 0x2060 && c <= 0x2064) return true;
  if (c >= 0x2066 && c <= 0x2069) return true;
  if (c == 0xFEFF) return true;
  if (c >= 0xE0000 && c <= 0xE007F) return true;
  return false;
}

/// Só remove os caracteres perigosos e corta no tamanho. Não mexe nos espaços
/// (serve enquanto a pessoa digita).
String stripUnsafe(String? s, {int max = kMaxLine, bool multiline = false}) {
  if (s == null || s.isEmpty) return '';
  final out = <int>[];
  for (final c in s.runes) {
    if (c == 0x0D) continue; // \r
    if (_isUnsafe(c, multiline)) continue;
    out.add(c);
    if (out.length >= max) break;
  }
  return String.fromCharCodes(out);
}

/// Texto pronto para guardar: sem caracteres perigosos, espaços arrumados,
/// sem pontas e com no máximo [max] caracteres. Em campo de uma linha, quebras
/// viram espaço; em multilinha, as quebras ficam (no máximo uma linha em branco
/// seguida).
String cleanText(String? s, {int max = kMaxLine, bool multiline = false}) {
  if (s == null || s.isEmpty) return '';
  final base = stripUnsafe(s.replaceAll('\r', ''), max: max * 2 + 16, multiline: multiline);
  String t;
  if (multiline) {
    final lines = [
      for (final l in base.split('\n')) l.replaceAll('\t', ' ').replaceAll(RegExp(r' {2,}'), ' ').trim()
    ];
    final b = StringBuffer();
    var blank = 0;
    for (final l in lines) {
      if (l.isEmpty) {
        blank++;
        if (blank > 1) continue;
      } else {
        blank = 0;
      }
      if (b.isNotEmpty) b.write('\n');
      b.write(l);
    }
    t = b.toString().trim();
  } else {
    t = base.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  final runes = t.runes.toList();
  if (runes.length <= max) return t;
  return String.fromCharCodes(runes.sublist(0, max)).trimRight();
}

/// O texto tem algo que [cleanText] tiraria (só para avisar a pessoa).
bool hasUnsafeChars(String s, {bool multiline = false}) {
  for (final c in s.runes) {
    if (c == 0x0D) continue;
    if (_isUnsafe(c, multiline)) return true;
  }
  return false;
}
