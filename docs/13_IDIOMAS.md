# Idiomas (português e inglês)

O app fala **português do Brasil** (padrão) e **inglês**. O idioma segue o aparelho e pode ser trocado em **Ajustes › Aparência e tela › Idioma / Language** (Auto, Português, English). Só o inglês de aparelho em inglês liga o inglês sozinho; qualquer outra língua fica em português.

## Como funciona

- **O texto no código é o português.** Todo texto que a pessoa lê é escrito `tr('Salvar')`. Em português, `tr` devolve o próprio texto; em inglês, procura a tradução no dicionário (`packages/afina_core/lib/i18n_en_*.dart`) e, se não achar, devolve o português (nunca uma tela vazia).
- **Valores entram por marcadores**: `tr('{0} aula{1} em {2}', [n, n == 1 ? '' : 's', mes])`. A tradução usa os mesmos marcadores e pode trocar a ordem (`'{2}, {1} {0}'`). Deixar um marcador de fora é permitido (o inglês não precisa do plural em "ser{6}"); usar um que o original não tem, não.
- **Contexto (`@@`)**: quando o mesmo texto em português quer duas traduções, acrescente `@@contexto` à chave (`'{0} de {1}@@mês'`). O contexto só distingue a chave no dicionário e **nunca aparece na tela**.
- **Plural**: o padrão do app é `n == 1 ? '' : 's'` num marcador; funciona em inglês porque os substantivos usam "s" (lesson, student, absence, bar, task). Onde o plural não é só "s", use dois textos (`n == 1 ? tr('lição') : tr('lições')`).
- **Valores que o código guarda ou compara não são traduzidos**: códigos de erro (`NET-01`), chaves de API e do `SharedPreferences`, nomes técnicos, papéis (`aluno`/`professor` na URL). Isso **não** usa `tr`.
- **Constantes**: `tr` não é constante. Texto de tela em `const Text('x')` vira `Text(tr('x'))` (sem `const`). Valor de `enum` ou parâmetro com padrão guarda o português puro marcado com `/*tr*/'x'` e **traduz ao ler** (`String get label => tr(_label)`).
- **Lógica nunca depende do texto exibido**: `ScaleType.isMinor` decide a grafia pelo tipo, não por `label.contains('menor')`; `isDefaultStudentName` aceita "Aluno K7QM" e "Student K7QM" (o nome padrão é gravado no idioma de quando o aluno entrou).
- **Notas**: em inglês aparecem como C D E F G A B (e `C♯`, `B♭`); o português usa Dó Ré Mi.
- **Datas**: dia/mês por padrão; mês/dia só no inglês dos EUA, Canadá e Filipinas (`Lang.monthFirst`, `fmtDayMonth`). Use sempre `fmtDayMonth`/`fmtDayMonthYear`, nunca `dd/mm` montado à mão.
- **Avisos**: o tipo (sucesso/atenção/informação) sai de palavras-chave, em português e em inglês (`lib/ui/toast_kind.dart`); `test/ui/toast_kind_en_test.dart` guarda o conjunto em inglês.

## Troca de idioma

`AppState.setLangPref` grava a escolha (chave `lang`: `auto`, `pt`, `en`) e aplica. **Na web a página recarrega**, porque algumas listas ficam guardadas na memória (dias da semana, nomes de notas, catálogo de erros) e só nascem no idioma novo ao reiniciar. Fora da web as telas se refazem na hora, mas essas listas só mudam ao reiniciar o app.

## O que mais acompanha o idioma

| Parte | Como |
|---|---|
| Mensagens do servidor (`api/link.js`, `coach.js`, `_lib/library.js`) | O servidor responde em português; o app traduz ao mostrar (`trOrNull`). Cada mensagem tem entrada no dicionário (o `check_i18n` confere). |
| IA (`api/coach.js`) | O app manda `lang: 'en'`; o servidor acrescenta "Write the whole answer in English." ao prompt. Sem o campo (apps antigos) a resposta segue em português. |
| Lembretes de aula (`web/sw.js`) | O texto é montado no service worker. A página avisa o idioma (`nmPush.setLang`) e o service worker guarda numa cache à parte (`nm-lang`); sem aviso, usa o idioma do aparelho. |
| Textos do próprio Flutter (datas, "OK", copiar/colar) | `lib/ui/app_locale.dart` (`pt-BR` e `en`). |
| Páginas estáticas (`index.html`, `sobre.html`) e painel do administrador | Continuam em português. |

## Como acrescentar ou mudar um texto

1. Escreva em português: `Text(tr('Novo texto'))`.
2. Rode `node scripts/check_i18n.js`: ele lista o que falta traduzir.
3. Crie a tradução numa parte nova `packages/afina_core/lib/i18n_en_<nome>.dart` (`const Map<String, String> kEn<Nome> = { 'Novo texto': 'New text', };`) ou numa parte existente, e rode `node scripts/check_i18n.js --write` (atualiza `i18n_en.dart`).
4. Confira no navegador em 390×844, em português e em inglês: o inglês costuma ser mais longo.

`node scripts/check_i18n.js` (roda no CI) falha se faltar tradução, se a tradução usar marcador que o original não tem, se tiver cara de português (ã, õ, ç), se houver entrada repetida ou sobrando, ou se `i18n_en.dart` não incluir todas as partes.

## Ferramentas (já usadas uma vez)

- `scripts/i18n_codemod.js` envolve em `tr()` os textos de tela (regras em `scripts/lib/i18n_rules.js`); `i18n_fix_const.js` tira os `const` que deixaram de valer; `i18n_fix_enums.js` converte enums; `i18n_unwrap.js` tira o `tr()` de um texto técnico. Servem de consulta, não precisam rodar de novo.

## Custo

O dicionário inglês (~1.950 textos) vai no pacote do app: cerca de 160 KB de código-fonte (uns 55 KB comprimidos, +4% no download da web). Não há chamada nova à rede nem ao Redis.
