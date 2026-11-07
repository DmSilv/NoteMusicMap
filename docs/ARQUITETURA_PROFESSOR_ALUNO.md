# Professor e aluno: arquitetura de identidade, vínculo e dados

Planejamento (nada disso está implementado). Objetivo: começar **sem cadastro**, com identificação automática, e evoluir para contas, professores e acompanhamento **sem reconstruir o app**.

## 1. Princípios
1. **Local primeiro.** O aparelho continua sendo a fonte da verdade e funciona offline. A nuvem é opcional (o usuário liga a sincronização).
2. **A identidade é da PESSOA (perfil), não do aparelho.** O aparelho só guarda uma credencial do perfil. Se o código fosse preso ao aparelho, trocar de celular ou reinstalar perderia tudo.
3. **Código público não dá acesso.** O código de identificação serve para ser encontrado/vinculado; o acesso exige segredo + consentimento do aluno.
4. **Dados do aluno são do aluno.** O professor só vê o que o aluno vinculado autorizou, e só enquanto o vínculo existir.
5. **Dados imutáveis onde possível.** Sessões de exercício são só de acrescentar (não se editam), o que dá integridade e elimina conflito de sincronização.

## 2. Identidade em camadas
| Camada | O que é | Onde nasce | Para que serve |
|---|---|---|---|
| `profileId` | UUID do perfil (aluno, professor ou ambos) | no aparelho, no primeiro uso | dono de todos os dados |
| `profileSecret` | 256 bits aleatórios | no aparelho; o servidor guarda só o hash | provar que é o dono |
| `shareCode` | código curto legível (ex.: `K7QM-4TXD`, 32 símbolos sem 0/O/1/I, 7 sorteados + 1 de verificação) | sorteado junto com o perfil (o servidor garante unicidade e sorteia outro se colidir) | aparecer no QR/convite; **não** dá acesso |
| `deviceId` + token | um por aparelho | no aparelho | revogar um aparelho perdido sem afetar os outros |
| `account` | e-mail/Google (depois) | na fase 3 | reunir perfis e aparelhos |

### Papéis: todos são alunos; professor é uma capacidade
Não existe "conta de professor" separada nem tela de escolha no início. **Todo perfil começa como aluno**, usa o app inteiro e, se quiser ensinar, liga "Modo professor" nas configurações (`profiles.teacher_enabled`). O mesmo perfil pratica e ensina, então não há áreas duplicadas, e a mesma pessoa pode ser aluna de um professor e professora de outros.
- Permissão no servidor: rotas de professor exigem `teacher_enabled = true` **e** vínculo ativo com o aluno; rotas de aluno só exigem ser o dono do perfil.
- Desligar o modo professor esconde a área e suspende os vínculos como professor (os dados dos alunos ficam preservados por 30 dias e voltam se religar).
- Na Fase 1 isso já vale localmente: o botão fica em `Profile.teacher`.

Fluxo anônimo (fase 1–2): app gera `profileId`+`secret`+`shareCode`; mostra "Meu código" (QR). Nenhum dado pessoal obrigatório (nome é opcional).

## 3. Modelo de dados (Postgres)
- `profiles(id, share_code unique, teacher_enabled default false, name?, claimed_account_id?, merged_into?, created_at, deleted_at)`
- `devices(id, profile_id, token_hash, label, created_at, last_seen_at, revoked_at)`
- `accounts(id, email unique, created_at)` (fase 3)
- `teacher_links(id, teacher_id, student_id, status[pending|active|revoked], scopes jsonb, created_at, accepted_at, revoked_at)`
- `link_invites(code_hash, teacher_id, expires_at, used_at)` — convite de uso único, validade curta
- `sessions(id uuid gerado no cliente, profile_id, device_id, schema_v, started_at, title, accuracy, mean_abs_cents, steps jsonb, origin[self|teacher_device], supervised_by?, deleted_at)`
- `assignments(id, teacher_id, student_id, spec jsonb, goal, due_at, status, done_session_id?)`
- `teacher_notes(id, teacher_id, student_id, text, visible_to_student, created_at)` — **privadas ao professor por padrão**
- `audit_log(id, actor_id, action, target, at)` — vínculo, revogação, exportação, exclusão

Notas: `sessions.id` vem do cliente (idempotência: reenviar não duplica). Nada de áudio no servidor, nunca.

## 4. Regras de negócio e autorização
1. Cada aluno tem **um `profileId` único**; o `shareCode` é único e verificável.
2. **Vincular:** o professor gera convite (código/QR/link, uso único, 15 min). O aluno abre, vê "Fulano quer acompanhar seus exercícios", escolhe o que compartilha (sessões, afinação por nota, tarefas) e **aceita**. Alternativa: o aluno mostra o `shareCode` e o professor pede vínculo; o aluno aprova.
3. **Isolamento:** o professor lê apenas alunos com vínculo `active` e dentro dos `scopes`. Nunca vê outros alunos; aluno nunca vê outros alunos. Sem vínculo, 404 (não 403, para não revelar existência).
4. **Revogação:** o aluno revoga a qualquer momento; vale na hora. O professor também pode encerrar. Dados antigos ficam com o aluno.
5. **Professor não edita dados do aluno:** só cria tarefas e observações próprias. Sessões feitas "em aula" no aparelho do professor entram com `origin=teacher_device` e só são vinculadas ao perfil do aluno se o aluno aceitar.
6. **Histórico antes do vínculo:** privado por padrão; o aluno escolhe compartilhar o passado ou só daqui para frente.
7. **Exportar e excluir (LGPD):** o titular exporta tudo (JSON) e pede exclusão (exclusão lógica e remoção definitiva em 30 dias). Menores: exigir confirmação de responsável antes do vínculo.
8. **Anti-abuso:** limites por IP/perfil/aparelho (a infraestrutura de fila da IA já tem o padrão), tentativas de código limitadas (5/min), códigos com validade e uso único.

Defesa em profundidade: todo acesso resolve `profile_id` **a partir do token, nunca de parâmetro do cliente**; além disso, políticas **RLS** no Postgres (`profile_id = current_setting('app.profile_id')`) e uma bateria de testes de autorização (matriz aluno/professor/estranho × cada rota).

## 4.1 Segurança
Tokens guardados só como hash (SHA-256); segredo mostrado uma vez e guardado no armazenamento seguro do aparelho; HTTPS; sem CORS aberto; rotação de token por aparelho; "Sair de todos os aparelhos"; registro de auditoria; sem dados pessoais em logs; relatórios por IA continuam anônimos (sem nome, sem observações).

## 5. Vários aparelhos e conta
- **Sem conta (parear aparelho):** no aparelho antigo, "Adicionar aparelho" gera token de pareamento de uso único (5 min, QR). O novo escaneia e recebe sua própria credencial para o **mesmo** `profileId`.
- **Criar conta depois:** e-mail por link mágico ou Google. `POST /account/claim` associa o perfil atual à conta; o histórico existente permanece.
- **Entrar em aparelho novo com conta:** login → lista de perfis da conta → registra o aparelho.
- **Dois perfis para a mesma pessoa** (instalou de novo antes de entrar): `merge` em transação; sessões e vínculos são reapontados, o perfil antigo recebe `merged_into`, tudo auditado e idempotente.
- **Perdeu o aparelho sem conta:** só há recuperação se o usuário guardou a **chave de recuperação** (texto/QR gerado na fase 1). O app avisa isso ao ligar a sincronização.

## 6. Sincronização (local-first)
- Cliente mantém **outbox** de eventos (criar sessão, tarefa, nota) com id próprio; envia quando há rede; servidor responde idempotente.
- Download por **cursor** (`since=<seq>`) por tipo de dado. Sessões imutáveis = sem conflito; tarefas/notas: última escrita vence (hora do servidor); exclusões viram marcas (tombstones).
- Opt-in: a sincronização só liga com consentimento explícito (texto claro do que sobe).

## 7. Impacto no que existe
| Área | Mudança | Risco |
|---|---|---|
| `SessionRecord` | ganha `id` (UUID; sessões antigas recebem um id estável `L…` calculado da data e do título) e `origin`; o `v: 2` do JSON continua sendo o schema; JSON antigo continua lendo. **Feito na Fase 1** | baixo |
| `AppState` | extrair `ProfileStore`, `TeacherStore`, `SyncService`; a interface `Repository` (hoje `LocalRepository`; amanhã `RemoteRepository`) mantém a UI como está | médio (refatoração guiada por testes) |
| Professor local (MVP atual) | `Student.id` local vira "perfil pendente"; ao aceitar o convite, o histórico local sobe e o id local é mapeado para o `profileId` real | baixo |
| `api/` | novo `api/v1/*` (perfis, aparelhos, sessões, vínculos, tarefas, notas, exportar, excluir); `_lib/auth.js` (token → perfil), `_lib/db.js`; `coach.js` passa a usar o perfil em vez de só IP+aparelho | médio |
| Banco | Postgres gerenciado (migrações versionadas) | novo |
| IA | continua anônima; cotas por perfil | baixo |
| Política de privacidade e textos | atualizar (nuvem opcional, vínculo, exclusão) | obrigatório |
| CI | testes de autorização e de migração | novo |

## 8. Escolha de plataforma (decisão pendente)
- **Recomendação: Supabase (Postgres + Auth + RLS).** Tem **login anônimo que depois vira conta mantendo o mesmo id de usuário**, exatamente o caminho "começar sem cadastro e vincular depois"; link mágico e Google prontos; RLS nativo. Mantemos uma camada `Repository`/`api` própria para não ficar preso.
- Alternativa: Neon (Postgres) + autenticação própria. Mais controle, mais código e mais risco de segurança para manter.
- Em ambos: segredos só em variáveis de ambiente; nunca no app.

## 9. Fases (cada uma publicável sozinha)
1. **Identidade local** (sem servidor) — **FEITA**: `profileId`, segredo, `shareCode`, "Meu perfil" (código, QR, chave de recuperação, restaurar), `SessionRecord.id`/`origin`, interface `Repository` (`LocalRepository`), `teacher` no perfil. Arquivos: `packages/afina_core/lib/identity.dart`, `lib/data/repository.dart`, `lib/ui/profile_page.dart`. A chave de recuperação guarda a identidade (id, segredo, código), **não** o histórico: o histórico entre aparelhos vem na fase 2.
2. **Nuvem opcional:** banco, `api/v1`, sincronização das sessões do próprio aluno, exportar/excluir, testes de isolamento.
3. **Professor e aluno de verdade:** convites, consentimento, escopos, revogação, tarefas e observações na nuvem; painel do professor.
4. **Contas e vários aparelhos:** link mágico/Google, reivindicar perfil, pareamento por QR, mesclar perfis.
5. **Evolução:** turmas, lembretes, relatórios, painel web amplo, cobrança se fizer sentido.

## 10. Decisões que preciso de você
1. Plataforma: **Supabase** (recomendado) ou Postgres + auth própria?
2. Quem inicia o vínculo: **professor convida** (padrão proposto) ou também o aluno pode pedir?
3. O professor vê o **histórico anterior ao vínculo** só se o aluno liberar (proposto)?
4. Haverá **alunos menores de idade**? (muda o consentimento).
5. A sincronização começa **desligada** (proposto) ou ligada por padrão?
