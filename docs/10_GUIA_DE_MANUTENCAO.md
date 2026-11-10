# Guia de manutenção

Receitas passo a passo e as armadilhas que já custaram tempo.

## Receitas

### 1. Nova ação na API (`/api/link` ou outro)
1. Defina o contrato (corpo, resposta) — **só acrescenta**; não mude o que existe.
2. Em `api/link.js`: valide ids e tipos (regex, `normCode`), limpe texto (`clean`), cheque vínculo/permissão, aplique o limite certo (consulta × alteração).
3. Se há disputa (dois pedidos ao mesmo tempo), use operação atômica (`HSETNX`).
4. Se muda algo que o outro lado precisa ver, avance o **contador** do perfil dele (`lr dr kr sr vr ar` ou crie um novo e inclua em `rev`/`sync`).
5. Conte métrica se fizer sentido (`await metric('x')` e inclua `x` em `EVENTS` de `api/_lib/metrics.js`).
6. Teste em `api/*.test.js`: feliz, segurança, limites, entradas inválidas, **compatibilidade**; meça o custo.
7. Cliente: método em `lib/link/link_service.dart` (+ campo no `LinkReply`), uso em `AppState` (fila local se precisar reenviar), tela.
8. `node scripts/gen_docs.js`; anote o custo em `CUSTOS_E_REGRESSAO.md`.

### 2. Nova regra no núcleo
1. Arquivo em `packages/afina_core/lib/`, **Dart puro**, relógio por parâmetro.
2. Teste em `packages/afina_core/test/`.
3. `export` em `afina_core.dart` (cuidado com nomes repetidos: o compilador reclama de "exportado duas vezes").
4. Use no `AppState`/tela.

### 3. Nova tela
1. `lib/ui/xxx_page.dart`, lendo do `AppState` (`ListenableBuilder`).
2. Título curto (e com o papel quando importa: "Agenda do aluno"), botão voltar, ação principal com ícone.
3. Entrada no hub **só se** ela não duplicar um destino já presente na visão (atualize `hub_view.dart` e seus testes).
4. Textos longos vão para o "?" (`HelpButton`), não para a tela.
5. Confira em celular e tela larga.

### 4. Novo código de erro
1. Acrescente a entrada em `kErrorCatalog` (`afina_core/lib/errors.dart`) com gravidade, título, frase e ação.
2. Use `classifyError` ou `app.fail(mensagem, code: 'XXX-NN', where: ...)`.
3. Rode `node scripts/gen_docs.js` (atualiza `referencia/ERROS.md`) e o teste do catálogo.

### 5. Nova variável de ambiente
Leia em `api/_lib/config.js` (`env.NOME`), documente em [08_OPERACAO.md](08_OPERACAO.md), configure na Vercel e faça **novo deploy**. Nunca coloque o valor no repositório.

### 6. Nova chave no Redis
Defina com um comentário na mesma linha (`const X = (c) => \`x:${c}\`; // o que guarda`) — o gerador lê esse comentário para `referencia/DADOS.md`. Pense em **expiração/limpeza** para não crescer sem fim.

### 7. Novo contador de métrica
Inclua o nome em `EVENTS` (`api/_lib/metrics.js`), chame `metric('nome')` onde acontece, e mostre no painel (`admin.html`: `render`/jornada) e no custo (`COST` em `api/admin.js`). Cada contador custa **+1 comando** por evento.

### 8. Publicar
1. Testes (ver [06_TESTES.md](06_TESTES.md)), `node scripts/check_docs.js`, conferir na tela.
2. Mostrar ao dono: o que muda, testes, impacto para quem usa, rollback.
3. **"Sim" explícito** → `git push` (se lento, em segundo plano) → seguir adiante.

### 9. Girar chaves
- **Painel**: trocar `ADMIN_KEY` na Vercel + redeploy.
- **VAPID**: `node scripts/gen_vapid.js`; trocar `VAPID_PUBLIC_KEY/PRIVATE_KEY`; quem já se inscreveu precisa reativar o lembrete.
- **Chaves de IA**: trocar a variável correspondente; redeploy.

## Armadilhas conhecidas
| Armadilha | Como evitar |
|---|---|
| **12 funções na Vercel**: arquivo de teste em `api/` conta | Manter `.vercelignore`; conferir `ls api/*.js | grep -v test | wc -l` |
| `flutter test` não roda aqui | Lógica no núcleo (`dart test`); interface por `flutter analyze` + tela |
| `notifyListeners()` dentro de `build` | Usar `Future.microtask(notifyListeners)` (como em `reportError`) |
| Nome colidindo no `afina_core.dart` | Prefixar/renomear (ex.: `buildErrorReport`, `summarizeTasks`) |
| App antigo em cache (PWA) | API sempre retrocompatível; o painel só reabre bug por versão **nova** |
| Dia "de hoje" no painel | Horário de Brasília (UTC−3, sem horário de verão); o dia é parcial |
| Contagem de aparelhos ≠ pessoas | HyperLogLog (≈1%) e reinstalação conta como novo |
| `localhost` não envia estatísticas/erros | De propósito; para testar o painel, use um servidor local com `allowMemory` |
| Shell no Windows: *heredoc*, barras invertidas e `sed` com regex quebram scripts | Escrever arquivos com a ferramenta de escrita; usar scripts `.js` em vez de linhas de comando longas; conferir o resultado (`cat -A`) |
| `git push` muito lento | Rodar em segundo plano e conferir `git status -sb` |
| Avisos de "LF será substituído por CRLF" no Git | Inofensivos (Windows) |
| Testes dependem do emulador de Redis (`store_cmd.js`) | Ao usar um comando novo do Redis, **emule-o** lá (ex.: `HSETNX`, `HMGET`, `ZREVRANGEBYSCORE`, `DEL`) |
| Mudar um texto que o teste confere | Atualizar o teste junto; textos de regra estão no núcleo |

## Onde procurar quando algo quebra
1. Aba **Bugs** do painel (pilha + trilha + versão + plataforma).
2. Ajustes › Diagnóstico › **Problemas recentes** no aparelho do usuário (código `E-XXXX`).
3. `git log --oneline` e [11_HISTORICO.md](11_HISTORICO.md) para saber o que mudou por último.
4. [referencia/ARQUIVOS.md](referencia/ARQUIVOS.md) para achar o arquivo certo.
