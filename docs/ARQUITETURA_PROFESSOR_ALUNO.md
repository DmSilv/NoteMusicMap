> **Documento histórico (planejamento inicial).** O que foi realmente construído **não usa Postgres nem contas**: usa Redis, perfis anônimos (código + segredo) e vínculo online. A arquitetura atual está em [01_ARQUITETURA.md](01_ARQUITETURA.md) e as decisões em [09_DECISOES.md](09_DECISOES.md).

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
2. **Vincular (decidido):** o professor só precisa do **código do aluno** (`shareCode`), sem cadastro completo. Ele digita o código ao criar o aluno (campo opcional já existe na Fase 1) e o servidor cria um **pedido pendente**. O aluno vê "Fulano quer acompanhar seus exercícios", escolhe o que compartilha (sessões, afinação por nota, tarefas) e **aceita**. Como o código é semipúblico, é o aceite do aluno que dá acesso, nunca o código. Alternativa para quem está presencialmente: convite do professor por QR/link de uso único (15 min).
   - **O que o aluno vê depois do vínculo** ("Minhas aulas", Fase 3): as tarefas passadas, as orientações e observações que o professor marcou como visíveis (`visible_to_student`), o conteúdo/atividades compartilhados, e o próprio histórico e desempenho (que já são dele). Pode ver quem é o professor, o que está compartilhado e encerrar o vínculo.
   - **Conteúdo das aulas:** nova tabela `lesson_items(id, teacher_id, student_id|group, kind[orientacao|atividade|material], title, body, created_at)`; o aluno só lê os que são dele.
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
2. ~~Quem inicia o vínculo~~ **Decidido:** o professor digita o código do aluno e o aluno aceita; convite por QR/link como alternativa presencial.
3. O professor vê o **histórico anterior ao vínculo** só se o aluno liberar (proposto)?
4. Haverá **alunos menores de idade**? (muda o consentimento).
5. A sincronização começa **desligada** (proposto) ou ligada por padrão?

## 11. Melhorias da área do professor (vínculo por QR, tarefas, voz)

**Feito (sem servidor):**
- **QR do aluno = link** `https://…/?aluno=K7QM-4TXK`. A câmera comum do celular do professor abre o app (web/PWA) já com o código; o app abre o cadastro "Novo aluno" com o código preenchido (liga o modo professor se preciso). O app valida o código (verificação) e avisa se já está na lista ou se é o próprio código.
- **Tipos de tarefa:** escala/arpejo (medida pelo app, concluída sozinha), **método e lição** (ex.: Suzuki · Livro 2 · Lição 5, com sugestões Suzuki, Ševčík, Kayser, Wohlfahrt, Mazas, Schradieck, Kreutzer, Dont, Flesch, Hanon e os métodos já usados), **repertório** (peça + trecho/compassos) e **outra atividade**. Todas têm **observações livres** (o que merece atenção, o que estudar mais) e podem ser editadas. Só a escala é auto-concluída; as demais o professor marca.
- **Ditado por voz:** o teclado do celular (Android/iOS) já tem microfone para ditar em qualquer campo; o formulário avisa isso. Não há botão de voz próprio ainda.
- **Privacidade:** o relatório por IA nunca leva texto livre (título, lição, observação): só números e o tipo da tarefa.

**Planejado (precisa de plugin nativo e teste em aparelho):**
1. **Leitor de QR dentro do app** (`mobile_scanner`): botão "Ler QR do aluno" em "Novo aluno" para o professor que não usa a câmera do sistema. Pede permissão da câmera; a web usa a câmera do navegador. Aceita o mesmo link e o texto `notemusic:CÓDIGO`.
2. **Botão de voz no app** (`speech_to_text`): microfone ao lado dos campos de observação e lição, para web (Chrome/Edge/Safari), Android e iOS. Transcrição fica no aparelho/navegador; nada é enviado pelo app.
3. **Visão do aluno ("Minhas aulas")**: depende da nuvem (Fase 2/3). Ao aceitar o vínculo, o aluno vê tarefas (inclusive método/lição/repertório), as observações que o professor marcar como visíveis e o próprio histórico; pode marcar uma tarefa como feita ("estudei") e o professor vê.
4. **Biblioteca de métodos do professor**: lições e repertório reutilizáveis entre alunos (hoje só o nome do método é sugerido de novo).

**Navegação (princípios):** um único caminho para cada coisa (perfil e professor pelo ícone da barra; área do professor → aluno → tarefas/observações); mesma linguagem nos botões ("Nova tarefa", "Anotar", "Gerenciar"); explicações curtas dentro da própria tela (guia "Como funciona", dicas nos campos); o aluno nunca vê ferramentas de professor.

## 12. Atualização: leitor de QR, voz e biblioteca de métodos (feitos)
- **Leitor de QR com câmera** (`mobile_scanner`) para professor e aluno, sempre com digitação manual na mesma tela. Professor: "Ler QR do aluno" (home da área do professor e dentro de "Novo aluno"). Aluno: Meu perfil › Meu professor › "Ler QR do professor". O professor mostra o QR dele na aba Professor (`?professor=CÓDIGO`). O QR do aluno é `?aluno=CÓDIGO`. Aceita também o código puro e `notemusic:CÓDIGO`. Sem permissão de câmera, a tela explica e segue pela digitação. O vínculo do aluno com o professor fica só **registrado neste aparelho** até existir sincronização (Fase 2/3). Web: `vercel.json` passou a liberar `camera=(self)`.
- **Escrita por voz** (`speech_to_text`) com botão de microfone nos campos de texto livre: nome do aluno, método, lição, observações da tarefa, observação do aluno, renomear, métodos, comentário da nota e pesquisa. Pergunta uma vez como funciona (o serviço de voz é do aparelho/navegador). Desliga o afinador antes de ouvir.
- **Biblioteca de métodos e lições** ("Meus métodos e lições"): cadastrar, editar, excluir e copiar a lista em texto. A importação por texto foi removida em nov/2026: cada método e lição é cadastrado um a um. A biblioteca aprende sozinha com o que o professor digita nas tarefas e oferece as lições do método como atalhos.
- **Não feito:** importar de arquivo (CSV/planilha) por seletor de arquivos; hoje se cola o texto. Catálogo pronto de lições de métodos publicados não foi incluído (conteúdo protegido e sem fonte confiável): apenas nomes de métodos como sugestão.

## 13. Correções: auto-cadastro, câmera nas permissões e vibração
- **Regras de cadastro de aluno** (`checkStudentEntry`, no núcleo, testadas): o código não pode ser o do próprio professor ("aluno de si mesmo"), nem o do professor dele, nem repetir o de outro aluno; sem código, o nome não pode ser o do próprio perfil; nome repetido só é aceito se os dois alunos têm códigos diferentes. Valem ao digitar, ao ler QR (a tela do leitor recusa e deixa tentar de novo), ao abrir link `?aluno=`, ao editar o código e ao **importar** dados de aluno (antes a importação não conferia nada). "Meu professor" recusa o próprio código e o de um aluno seu. **No servidor (Fase 2)** a mesma regra vira restrição do banco: `teacher_id <> student_id` em `teacher_links` e vínculo único por par.
- **Câmera na lista de permissões** (Configurações › Permissões e privacidade), com status (liberada / sem permissão / ainda não pedida), botão Permitir/Testar e instrução de como liberar depois de negar. O status é registrado quando o leitor abre a câmera ou recebe a negativa.
- **Vibração na web:** o plugin `vibration` só implementa Android/iOS nativos; na web ele falhava e o app dizia "indisponível". Agora o app chama `navigator.vibrate` direto (Chrome/Edge/Firefox do Android, depois de um toque na tela). **iPhone/iPad:** a Apple não oferece vibração a sites nem a apps da tela inicial; só um app nativo da App Store teria. O texto de "indisponível" agora explica o motivo (iPhone, navegador sem suporte ou computador).

## 14. Vínculo online automático (feito, camada mínima)
- **O que faz:** quem lê o QR (ou digita o código) do outro cria o vínculo, e ele aparece **nos dois aparelhos**: o aluno que lê o QR do professor entra sozinho na lista do professor; o professor que lê o QR do aluno aparece nos "Meus professores" do aluno. Sem aceite: ler o QR de alguém é o ato de consentimento. Qualquer lado pode encerrar.
- **Como:** `api/link.js` (POST) sobre o **Upstash Redis** (hashes por perfil: `u:<código>` guarda o hash do segredo e o apelido; `ut:` alunos de cada professor; `us:` professores de cada aluno). O dono de um código é quem o usou primeiro com um segredo (o do perfil); depois só ele consegue agir. Limites: 60 alterações/hora por perfil e 20 tentativas erradas/hora por origem. Ninguém se vincula a si mesmo (também no servidor). Sem Redis a API devolve 503 e o app segue só no aparelho.
- **"Tempo real":** o app consulta o servidor a cada 15 s enquanto uma tela de vínculos (Perfil ou Área do professor) está aberta, e uma vez ao abrir o app (se o vínculo online estiver ligado). Não é conexão contínua (a Vercel não oferece WebSocket); o atraso típico é de até ~15 s. Cada consulta usa 3 comandos do Redis.
- **Consentimento e privacidade:** o vínculo online fica **desligado** até a pessoa vincular alguém ou ligar a chave no perfil. O servidor guarda só código, apelido, hash do segredo e datas.
- **Segurança, limites conhecidos:** o código é semipúblico, então quem souber o código de um aluno pode criar um vínculo com ele (aparece na lista do aluno, que pode encerrar). Por isso **nenhum dado do aluno** passa por esse vínculo ainda: histórico, tarefas e observações continuam locais. O compartilhamento deles exigirá autorização explícita do aluno (próxima etapa), e um "bloquear professor".
- **Aluno removido pelo professor:** o vínculo é desfeito no servidor (e some da lista do aluno). **Aluno que encerra:** fica na lista do professor com o selo "Encerrado pelo aluno", e o histórico local é mantido.
- **Para ligar em produção:** criar o Upstash Redis (já listado em `.env.example`). Cota gratuita: confira o limite diário de comandos do plano; com muitos usuários com a tela aberta, considere o plano pago ou migrar o vínculo para o Postgres (Supabase).

## 15. Instalar no celular (feito)
- **Aviso fixo no alto da tela inicial** ("Instale o Notemusic no celular" + botão Instalar), só no navegador, em celular/tablet (ou no computador, quando o navegador libera a instalação) e enquanto o app não estiver instalado. "X" esconde por 7 dias; se a pessoa recusa a janela do navegador, esconde por 3 dias; "Já instalei" ou instalar de fato esconde de vez. Também há **Configurações › Sobre › Instalar no celular**.
- **Chrome/Edge (Android e computador):** o app guarda o evento `beforeinstallprompt` (script no `index.html`) e o botão abre a janela de instalação do navegador com um toque.
- **iPhone/iPad e navegadores sem a janela (Firefox, outros):** o botão mostra o passo a passo (Compartilhar › Adicionar à Tela de Início; ou menu ⋮ › Instalar app). A Apple não permite instalar com um toque.
- **Manifesto:** `id`, `lang pt-BR`, categorias; já tinha ícones 192/512 e maskable, `display: standalone` e service worker do Flutter.
- **Fora do escopo:** app de loja (Play Store/App Store). O app nativo existe no projeto (Android/iOS), mas publicar nas lojas exige contas de desenvolvedor, ícones/capturas e revisão; é um passo separado.

## 16. Auditoria de regras e vibração; modo desafio do metrônomo
**Regras (furos corrigidos):** renomear aluno agora segue as mesmas regras do cadastro (nome próprio e duplicado); trocar o código de um aluno já vinculado desfaz o vínculo antigo no servidor; restaurar outro perfil zera os vínculos da identidade antiga; "Apagar tudo" desfaz os vínculos no servidor (melhor esforço); importações têm limite de tamanho (aluno 3 MB; métodos 300 KB, 500 métodos, 8000 lições); ligar o microfone só vibra se a vibração estiver ligada. **Mudança de regra:** professor e aluno podem ser mútuos (um ensina o outro); o que continua proibido é ser aluno de si mesmo (app e servidor).

**Vibração (causa e correção):** o evento do metrônomo (bolinha e vibração) era lido pela *tela* do metrônomo, que para quando se troca de aba; agora o app lê os cliques (a cada 10 ms) e vibra em qualquer aba. Vibra só no tempo mais recente (sem rajada após travamento). Vibração mais longa (30 ms; 50 ms no acento) para ser sentida. Na web usa `navigator.vibrate` (Android); iPhone continua sem suporte do navegador. Outras ferramentas que vibram: fim do Pomodoro e do tempo personalizado (chave própria), passo de escala (chave "Vibrar"), microfone ligado (agora respeita a chave).

**Modo desafio ("sabotagem"):** `rhythm_challenge.dart` (núcleo) + motor do metrônomo. Surpresas temporárias: mais rápido, mais lento, alternado, ou silêncio sem som e sem marcação; depois volta sempre ao andamento original. Regras: começa normal; sempre há ≥ 2 compassos normais entre surpresas; níveis Leve (±6–12%, silêncio 1–2 compassos), Médio (12–22%, 2–3), Intenso (20–35%, 2–4); funciona junto com o treino de andamento (varia em torno do andamento que o treino subiu). Ao parar, resume quantas mudanças e silêncios houve. Testes: 22 casos no núcleo e no motor.

## 16. Auditoria de regras, vibração e modo desafio do metrônomo
**Furos achados e corrigidos (mesma família do "aluno de si mesmo"):**
- *Renomear aluno* ignorava as regras de cadastro (dava para pôr o seu nome ou o de outro aluno): agora usa `checkStudentEntry`.
- *Trocar o código de um aluno vinculado* deixava o vínculo antigo no servidor: agora desfaz o antigo.
- *Apagar tudo* e *restaurar perfil* deixavam vínculos órfãos/da identidade antiga: o primeiro desfaz os vínculos no servidor (melhor esforço), o segundo recomeça a lista de professores e reavalia os alunos.
- *Ligar o microfone* vibrava mesmo com a vibração desligada: agora respeita a chave.
- *Importações* sem limite: aluno ≤ 3 MB de texto; métodos ≤ 300 KB, 500 métodos e 8000 lições.
- *Vínculo mútuo* (A é professor de B e B de A) passou a ser **permitido** (o servidor já permitia); a regra antiga "professor não pode ser aluno" era mais restritiva do que o necessário e inconsistente com o cadastro automático. O que continua proibido é ser aluno/professor de si mesmo.

**Vibração:** o motor de eventos do metrônomo saiu da tela do metrônomo e foi para o app (`_pumpMetro`, a cada 10 ms). Antes, a bolinha e a vibração só rodavam com a aba do metrônomo aberta (o `Ticker` da tela é desligado nas outras abas). Agora vibram em qualquer aba: 50 ms no tempo forte, 30 ms nos demais (18 ms era curto demais para sentir). Se o app ficar parado e acumular tempos, vibra uma vez só. Pomodoro/tempo personalizado e escalas já vibravam; só o microfone ignorava a chave.

**Modo desafio ("sabotagem"):** `RhythmChallenge` (Dart puro, determinístico) decide compasso a compasso: andamento mais rápido/lento por 2–6 compassos (às vezes acelera e depois freia), silêncio de 1–4 compassos (som e marcação na tela somem) e retorno de surpresa. Três níveis (leve ±6–12%, médio ±12–22%, intenso ±20–35%), sempre com os primeiros compassos normais, no mínimo 2 compassos normais entre surpresas, e **toda surpresa volta exatamente ao andamento configurado**. Funciona junto com o treino de andamento (varia em volta do BPM que o treino já subiu). Ao parar, mostra o resumo ("3 mudanças de andamento e 2 silêncios"). Escolhas ficam salvas.

## 17. Funcionar sem internet e instalar (service worker próprio)
- **Achado:** com o Flutter 3.47 o `flutter_service_worker.js` gerado é só um "mata-service-worker" (desregistra-se sozinho). Ou seja, o app **não** abria sem internet, ao contrário do que o texto do app dizia, e a instalação dependia só do manifesto.
- **Correção:** `web/sw.js` próprio (rede primeiro, cache como reserva; `/api/*` e `build-id.txt` nunca vão ao cache), registrado no `index.html`, que 8 s depois de carregar manda guardar tudo o que a página já baixou (assim funciona sem internet já na primeira vez). `web/flutter_bootstrap.js` próprio, sem registrar o service worker do Flutter. `vercel.json`: `sw.js` sem cache. O botão "Atualizar o app" continua valendo (desregistra e limpa os caches).
- **Teste:** Chrome real via script: abre o app, espera o cache (14 arquivos, incl. o motor gráfico), derruba o servidor, reabre: o app aparece completo. O painel de navegador do Claude não suporta service workers, então este teste não roda lá.
- **Limite:** o primeiro acesso precisa de internet; a IA e o vínculo online sempre precisam.

## 18. Lançamento
Pasta `divulgacao/` (fora do Git): plano, contas e e-mail, gravação, voz de IA, 8 roteiros de vídeo e textos prontos. No app: prévia do link (Open Graph), `CONTACT_EMAIL` (variável da Vercel) na política de privacidade e política sem a marca "rascunho".

## 19. Aulas: do professor para o aluno
- **Fluxo:** na ficha do aluno o professor toca em **Começar a aula**; há **Pausar/Retomar** e **Encerrar**. O relógio guarda só instantes (sobrevive a fechar o app). Ao encerrar, o app monta o pacote com as **tarefas e observações criadas entre o início e o fim** (até 30 tarefas e 10 observações) e o envia. O aluno vê em **Meu perfil › Minhas aulas** (tarefas por aula, caixa de "feita", botão "Treinar" nas escalas).
- **Modelo (núcleo):** `ActiveLesson` (aula em andamento), `LessonRecord` (histórico do professor, com o estado de envio: nulo = só neste aparelho, falso = a enviar, verdadeiro = enviada), `SharedLesson` (o que o aluno recebe). Tudo é limpo com `cleanText` ao ler.
- **API (`POST /api/link`, mesma autenticação código+segredo):**
  - `{action:'lesson', other:<código do aluno>, lesson:{id,t,d,tn,tasks[],notes[]}}` (professor): exige vínculo existente **e que o aluno já tenha reivindicado o código** (senão `409 student_not_ready`, e o app tenta de novo depois). O servidor limpa e limita (30 tarefas, 10 observações, textos, kinds fixos) e guarda em `ul:<aluno>` no campo `professor:idAula`; mantém as 60 mais recentes; atualiza `lr` (revisão) no perfil do aluno.
  - `{action:'lessons'}` (aluno): devolve as aulas dos professores **ainda vinculados** (até 60). Limite de 240 consultas/hora.
  - `sync` devolve `lr`; o aluno só busca aulas quando `lr` mudou (nenhum comando extra no Redis por consulta).
  - `unlink` apaga as aulas daquele professor para aquele aluno.
- **Offline/sem servidor:** a aula fica guardada com selo "aguardando envio" e é enviada na próxima atualização do vínculo; sem código do aluno ou sem vínculo online ela fica só no aparelho do professor.
- **Privacidade:** passam a ir ao servidor, por aula, os textos das tarefas e observações. Nunca áudio nem o histórico de exercícios. A política dentro do app foi atualizada.
