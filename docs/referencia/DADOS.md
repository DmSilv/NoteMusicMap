# Dados: Redis e armazenamento local

> **Gerado automaticamente** por `scripts/gen_docs.js` a partir do código. Não edite à mão: rode `node scripts/gen_docs.js`.
> Chaves lidas dos comentários do código. Para mudar a descrição de uma chave, edite o comentário na linha onde ela é definida.

## Redis (Upstash)

Tudo guardado no servidor é anônimo: código de perfil, apelido, datas e o necessário para o vínculo. Nunca áudio, e-mail ou IP.

### Vínculo, aulas, agenda, tarefas e horários (`api/link.js`)

| Chave | Conteúdo |
|---|---|
| `u:<code>` | hash do perfil: h (hash do segredo), n (apelido) |
| `ut:<code>` | alunos deste professor: aluno -> JSON |
| `us:<code>` | professores deste aluno: professor -> JSON |
| `ul:<code>` | aulas deste aluno: "professor:idAula" -> JSON |
| `sl:<code>` | aulas marcadas pelo professor: idAula -> JSON |
| `ss:<code>` | aulas marcadas para este aluno: "professor:idAula" -> JSON |
| `ps:<code>` | aparelhos com notificação: hash do endereço -> inscrição |
| `av:<code>` | horários disponíveis do professor: idHorário -> JSON |
| `tk:<code>` | horários já pegos (trava contra dois alunos): idHorário -> aluno |
| `vd:<code>` | decisões do professor sobre as tarefas deste aluno: "professor:idAula:idTarefa" -> JSON |
| `dn:<code>` | tarefas que os alunos deste professor marcaram: "aluno:idAula:idTarefa" -> JSON |

### Índice de perfis para o painel (`api/_lib/profiles.js`)

| Chave | Conteúdo |
|---|---|
| `pf:last` | código -> última atividade (ms) |
| `pf:new` | código -> quando entrou (ms) |
| `pf:t` | código -> última atividade, só quem tem alunos |
| `pf:s` | código -> última atividade, só quem tem professor |
| `pf:on` | código -> último sinal de vida (presença), de 10 em 10 minutos |
| `pf:hot` | origem+dia -> quando passou de 30 perfis novos (aviso no painel) |

### Estatísticas anônimas de uso (`api/_lib/metrics.js`)

| Chave | Conteúdo |
|---|---|
| `st:hll:all` | aparelhos distintos de todos os tempos (HyperLogLog) |
| `st:hll:d:<d>` | aparelhos distintos do dia |
| `st:ct:d:<d>` | contadores do dia (hash): open, new, lesson, slot, remind, link |
| `st:dim:d:<d>` | aparelhos por plataforma/instalação/versão/origem do link no dia (hash) |
| `st:hll:d:<d>:tab:<t>` | aparelhos distintos que abriram cada aba no dia |
| `st:cnt:all` | totais (hash): profiles, links |
| `st:online` | conjunto ordenado: aparelho -> última batida (ms) |

### Relatórios de erro (`api/_lib/errors_lib.js`)

| Chave | Conteúdo |
|---|---|
| `er:f:<fp>` | hash: n, st (status), first, last, c, s, w, msg + contadores v:/p:/i: |
| `er:fd:<fp>` | HyperLogLog de aparelhos afetados |
| `er:t:<fp>` | hash: dia -> quantas vezes |
| `er:o:<fp>` | lista: últimas ocorrências |
| `er:idx` | zset: fp -> última vez |
| `er:rs` | hash: fp -> JSON { at, build } |
| `er:n` | hash: fp -> anotação do admin |
| `er:b` | hash: build -> primeira vez visto |
| `er:d:<d>` | hash do dia: total, critical, action, info, hHH |

### Painel do administrador (`api/admin.js`)

| Chave | Conteúdo |
|---|---|
| `pf:bl` | conjunto dos perfis bloqueados (para contar sem varrer) |

## Armazenamento local do app (`SharedPreferences`)

No navegador aparecem no `localStorage` com o prefixo `flutter.`. Tudo fica no aparelho.

| Chave | Arquivos que usam |
|---|---|
| `activeStudent` | app_state.dart |
| `agenda` | app_state.dart |
| `agenda_in` | app_state.dart |
| `agenda_rev` | app_state.dart |
| `ai_consent` | coach_ai.dart |
| `ai_count` | coach_ai.dart |
| `ai_day` | coach_ai.dart |
| `ai_device` | coach_ai.dart, feedback_service.dart |
| `ai_last_text` | coach_ai.dart |
| `anchor` | app_state.dart |
| `auto_mic` | app_state.dart |
| `beats` | app_state.dart |
| `bpm` | app_state.dart |
| `cam_granted` | app_state.dart |
| `challenge` | app_state.dart |
| `claim_lessons` | app_state.dart |
| `clock_custom` | app_state.dart |
| `clock_sw` | app_state.dart |
| `customMin` | app_state.dart |
| `dictation_ok` | dictation.dart |
| `done_outbox` | app_state.dart |
| `done_rev` | app_state.dart |
| `error_log` | app_state.dart |
| `exFlow` | app_state.dart |
| `fb_answered` | feedback_service.dart |
| `fb_first` | feedback_service.dart |
| `fb_pending` | feedback_service.dart |
| `fb_rating` | feedback_service.dart |
| `fb_snooze_until` | feedback_service.dart |
| `fb_snoozes` | feedback_service.dart |
| `flash` | app_state.dart |
| `flats` | app_state.dart |
| `gain` | app_state.dart |
| `goal` | app_state.dart |
| `gridMig` | app_state.dart |
| `haptic` | app_state.dart |
| `history` | app_state.dart |
| `hold` | app_state.dart |
| `hub_view` | app_state.dart |
| `install_done` | app_state.dart |
| `install_hide` | app_state.dart |
| `instrument` | app_state.dart |
| `keepAwake` | app_state.dart |
| `latency` | app_state.dart |
| `lesson_active` | app_state.dart |
| `lessons_done` | app_state.dart |
| `lessons_in` | app_state.dart |
| `lessons_rev` | app_state.dart |
| `link_on` | app_state.dart |
| `link_pref` | app_state.dart |
| `micRationale` | app_state.dart |
| `my_teacher` | app_state.dart |
| `my_teachers` | app_state.dart |
| `nick_hide` | app_state.dart |
| `noteSwitch` | app_state.dart |
| `notices` | app_state.dart |
| `onboarded` | app_state.dart |
| `open_slots` | app_state.dart |
| `picks_rev` | app_state.dart |
| `pomo_cfg` | app_state.dart |
| `pomo_days` | app_state.dart |
| `pomo_state` | app_state.dart |
| `push_on` | app_state.dart |
| `refA` | app_state.dart |
| `report_mode` | app_state.dart |
| `roleCardHidden` | app_state.dart |
| `sens` | app_state.dart |
| `sessions` | app_state.dart |
| `sessions2` | app_state.dart |
| `showFreq` | app_state.dart |
| `sn_seen` | app_state.dart |
| `sound` | app_state.dart |
| `spellAuto` | app_state.dart |
| `split_l2` | app_state.dart |
| `split_r2` | app_state.dart |
| `stats_dims_day` | stats_service.dart |
| `stats_id` | stats_service.dart |
| `stats_on` | stats_service.dart |
| `stats_origin` | stats_service.dart |
| `stats_tabs` | stats_service.dart |
| `study` | app_state.dart |
| `studyMode` | app_state.dart |
| `sub` | app_state.dart |
| `system` | app_state.dart |
| `teacherMode` | repository.dart |
| `teacherPin` | app_state.dart |
| `theme` | app_state.dart |
| `timbre` | app_state.dart |
| `toneVol` | app_state.dart |
| `tonicPc` | app_state.dart |
| `transpose` | app_state.dart |
| `tunerMode` | app_state.dart |
| `unlink_students` | app_state.dart |
| `unlink_teachers` | app_state.dart |
| `upd_hide` | app_state.dart |
| `verdict_outbox` | app_state.dart |
| `verdict_rev` | app_state.dart |
| `verdicts` | app_state.dart |

Total: **98** chaves locais.
