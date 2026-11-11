# Testes

## Como rodar tudo
```bash
# Núcleo (Dart puro) — ~500 testes
cd packages/afina_core && dart test

# Análise estática do app inteiro
flutter analyze

# API (Node, sem rede e sem dependências) — ~190 testes
node --test api/*.test.js api/_lib/*.test.js

# Documentação em dia (referência gerada, links, cobertura, limite de 12 funções)
node scripts/check_docs.js
```
> **Atenção:** neste ambiente de desenvolvimento `flutter test` **não roda**; a lógica testável mora no núcleo (`dart test`) e a interface é conferida com `flutter analyze` + olhando a tela.

## O que cada camada garante
| Camada | Onde | O que cobre |
|---|---|---|
| Núcleo | `packages/afina_core/test/*_test.dart` | Afinação, detector (<0,5 cent em tons limpos), metrônomo sem deriva, grade, escalas, agenda, aulas, **status de tarefas**, **horários livres**, **fase e permissões da aula**, **visões do hub** (sem repetição/mistura), **erros** (catálogo, classificação, higienização, histórico), relatório de erro, markdown da IA |
| API | `api/*.test.js` | Vínculo e segurança (`link.test.js`), agenda e lembretes (`agenda.test.js`), horários livres (`avail.test.js`), painel (`admin.test.js`, `painel_precisao.test.js`), suporte do painel (`support.test.js`), presença online (`presence.test.js`), indicadores de saúde (`indicators.test.js`), aviso de bug grave, precisão dos bugs e busca por apelido (`admin_push.test.js`), relatórios de erro e bugs (`errors.test.js`), IA (`coach.test.js`), feedback, estatísticas, **guardrails** (`guardrails.test.js`) |
| Estático | `flutter analyze` | Tipos, imports, lints |
| Visual | Chrome em tamanho de celular | Cada pacote é conferido na tela antes de publicar |

### Estilo dos testes da API
- Memória no lugar do Redis (`allowMemory: true` + emulador `store_cmd.js`); relógio fixo (`now: () => NOW`).
- Cada ação nova testa: caminho feliz, **segurança** (quem não pode), **limites**, entradas inválidas e **compatibilidade** (campos antigos intactos).
- Custo: `errors.test.js` mede comandos do Redis por evento; novas ações devem medir e anotar o custo.

## Matriz de botões e regressão
- **Matriz de botões** (tela × botão × resultado esperado): [MATRIZ_BOTOES.md](MATRIZ_BOTOES.md).
- **Roteiro manual de regressão** (8 passos com dois aparelhos): [CUSTOS_E_REGRESSAO.md](CUSTOS_E_REGRESSAO.md).
- O que **ainda não foi testado em condições reais**: push no Android e iPhone, validar/devolver e pegar horário entre dois aparelhos, painel com dados reais, som do pedal.

## Como testar a interface sem tocar na produção
O app de teste local (`http://localhost:...`) **não envia** estatísticas nem relatórios de erro (de propósito). Para ver telas com dados:
1. `flutter build web --release` (ou `--dart-define=DEV_DEMO=true --output build/web_demo` para botões de teste de erro).
2. Servir `build/web` com um servidor estático simples (sem repassar `/api`) para não criar perfis reais.
3. Semear `localStorage` (`flutter.profile`, `flutter.students`, `flutter.agenda_in`…) pelo console do navegador.
4. Para o painel `/admin` use um servidor local que monte os handlers de `api/` com `allowMemory: true` e semeie perfis, estatísticas e erros.

## Antes de publicar (checklist)
1. `dart test` (núcleo) e `node --test` (API) verdes; `flutter analyze` limpo.
2. `node scripts/check_docs.js` sem problemas (rode `node scripts/gen_docs.js` antes se mexeu em arquivos, API, chaves ou erros).
3. Conferido na tela (celular e, se mexeu em layout, tela larga).
4. Custo de Redis estimado/medido para qualquer ação nova.
5. Contagem de funções em `api/` ≤ 12 (`ls api/*.js | grep -v test | wc -l`).
6. **"Sim" explícito do dono**; depois do push, **não** ficar esperando o deploy (conferir só se houver problema).
