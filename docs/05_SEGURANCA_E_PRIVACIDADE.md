# Segurança e privacidade

## O que o app coleta e o que nunca coleta
| Coleta (anônima) | Onde | Para quê |
|---|---|---|
| Código de perfil, apelido opcional, datas do vínculo | Redis | Vínculo professor ↔ aluno |
| Aulas, tarefas e observações **que o professor decide enviar** ao aluno | Redis | Entrega ao aluno |
| Estatísticas: um código aleatório do aparelho, tipo de aparelho/navegador, sistema, faixa de tela, idioma, tema, toque, microfone e notificações (categorias), versão, abas abertas | Redis (agregado) | Painel de uso |
| Relatórios de erro: código do erro, tela, detalhe **higienizado**, versão, aparelho, trilha de telas | Redis (agrupado) | Painel de bugs |
| Resumo de números de afinação (só se a pessoa pedir análise por IA) | Serviço de IA | Análise |

**Nunca**: áudio, e-mail, telefone, IP guardado, localização, o que a pessoa toca, nome real obrigatório. O som é analisado no próprio aparelho e descartado.

## Autenticação e acesso
- **Sem login**. O perfil se prova com **segredo de 256 bits** que só o aparelho tem; o servidor guarda **só o hash**.
- **Código público não dá acesso**: serve para ser encontrado; acesso exige o segredo e o vínculo.
- Rotas de professor exigem vínculo ativo com o aluno; rotas de aluno exigem ser o dono do perfil. Aluno nunca lê dados de outro aluno (testado).
- **Painel de admin**: chave (`ADMIN_KEY`; hoje aceita também `FEEDBACK_ADMIN_KEY`) **só no cabeçalho** `Authorization`, nunca na URL ou no corpo. Tentativa errada conta contra um limite (10/h por origem). Chave fica só na aba do navegador (`sessionStorage`).
- Respostas **nunca** trazem segredo, hash do segredo nem rastros internos (testado em `api/guardrails.test.js`).

## Guardrails (camada por camada)
**No app**
- Toda entrada de texto passa por `input_guard.dart` (limites e remoção de caracteres invisíveis/controle).
- Ações irreversíveis pedem **confirmação**: excluir aluno, desvincular, apagar tudo, apagar horário livre, vincular por convite/QR.
- Convites e QR são **validados** (formato + dígito verificador) e sempre confirmados antes de vincular.
- Botões que falam com o servidor **travam** durante o envio (evita toque duplo).
- Erros e relatórios passam por `sanitizeDetail` (sem código de perfil, e-mail, segredo, endereço completo, números longos).

**No servidor**
- Corpo com tamanho máximo; JSON inválido, lista, texto ou número → 400, nunca 500.
- `code` só aceita **texto** (lista/objeto não viram código).
- Ids por regex; chaves perigosas (`__proto__`, `constructor`) não contaminam nada (testado).
- Limites por perfil e por origem (consultas, alterações, tentativas erradas, perfis novos) e teto global de relatórios de erro.
- Higienização repetida no servidor; apelido sem caracteres invisíveis e com tamanho máximo.
- Erros de servidor não expõem detalhes internos.

**Cabeçalhos HTTP** (`vercel.json`): `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `X-Frame-Options: SAMEORIGIN`, `Permissions-Policy` (microfone/câmera só do próprio site), `Cross-Origin-Opener/Embedder-Policy`, `Strict-Transport-Security`, e **`Content-Security-Policy-Report-Only`** (só relata; testado localmente **aplicando** a política sem violações, incluindo o som WASM). Para passar a bloquear: renomear para `Content-Security-Policy` depois de ver o console de produção sem avisos.

## Administração de perfis
O painel permite **bloquear/liberar** e **excluir dados** (com confirmação digitando o código e registro no log). O apelido **não** é editável pelo painel (pertence ao usuário e voltaria no próximo sincronismo).

## Pontos de atenção conhecidos
- `FEEDBACK_ADMIN_KEY` ainda vale como alternativa à `ADMIN_KEY`. Quando a `ADMIN_KEY` própria estiver configurada na Vercel, remover o *fallback* em `api/_lib/config.js`.
- O segredo do perfil fica no armazenamento local do aparelho (inerente a um app sem login): quem tem acesso ao aparelho desbloqueado tem o perfil. A *chave de recuperação* deve ser guardada pelo usuário.
- CSP ainda em modo relatório.
