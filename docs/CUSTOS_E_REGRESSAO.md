# Custos (Redis/Vercel) e roteiro de regressão

Plano gratuito do Upstash: **500 mil comandos por mês**. `incr` com expiração custa 2–3 comandos.
Valores abaixo são aproximados e contam só o que o servidor faz por pedido.

## Custo por ação
| Ação | Quem | Comandos (aprox.) | Quando acontece |
|---|---|---|---|
| `rev` (consulta barata) | app | 0 extra (o perfil já é lido na autenticação) | a cada ~30 s com o app à frente, esticando até 4x sem novidade |
| `sync` | app | 3–4 | só quando um contador muda ou há algo a enviar |
| `lesson` (publicar aula) | professor | ~6 + limpeza ocasional | ao encerrar a aula |
| `done` (aluno marca "fiz") | aluno | 3 | ao marcar |
| `verdict` (validar/devolver) | professor | 3–4 | ao validar |
| `verdicts` / `dones` / `sched` / `lessons` | app | 3 | só quando o contador correspondente mudou |
| `sched_put` | professor | ~8 | ao marcar/mudar aula |
| `avail_put` | professor | 3–4 | ao publicar/apagar horário livre |
| `avail` | aluno | 4 | só ao abrir "Pegar horário" |
| `avail_take` | aluno | ~12 | ao pegar horário |
| `picks` | professor | 4 | só quando o contador `ar` mudou |
| Perfil novo | servidor | +3 | uma vez por perfil |
| Atividade (índice do painel) | servidor | 2–4 | no máximo a cada 6 h por perfil ativo |
| Painel: `kpis` / `list` / `detail` | admin | ~35 / ~27 / ~12 | só quando o admin abre ou toca em Atualizar |

## Limites (anti-abuso)
- Consultas: 240/h por perfil; alterações: 60/h por perfil; perfis novos por origem: limite diário.
- Horários livres: 100 por professor; aulas de um aluno com o mesmo professor: 12; tarefas marcadas guardadas: 1500 por professor.
- Painel: 10 chaves erradas por hora por origem.

## Armazenamento que cresce (e como é limpo)
- `tk:` (trava dos horários pegos): 1 linha por horário pego; limpa quando o aluno é desvinculado ou o perfil é excluído.
- `dn:` / `vd:`: limitadas a 1500; apagadas ao desvincular ou excluir.
- `adm:log`: últimas 200 ações.
- Pendência: `pf:*` (índices do painel) só diminuem quando o perfil é excluído pelo painel.

## Roteiro manual de regressão (antes de cada publicação grande)
Automático: `dart test` (packages/afina_core), `node --test api/*.test.js api/_lib/*.test.js`, `flutter analyze`.

Manual, com dois aparelhos/abas (professor e aluno), vínculo online ligado:
1. **Vínculo:** aluno lê o QR/código do professor → os dois lados mostram "Conectado"; desativar e reativar o vínculo.
2. **Tarefas:** professor encerra uma aula com 2 tarefas → aluno recebe; aluno marca "fiz" → professor vê "para validar";
   professor valida uma e devolve outra → aluno vê "validada" e "refazer"; aluno marca de novo a devolvida.
3. **Resumo:** professor toca em "Começar a aula" → resumo com para validar / pendentes / concluídas.
4. **Agenda:** professor marca aula (única e semanal) → aluno recebe; mover e cancelar; lembrete push chega (Android e iPhone).
5. **Horários livres:** professor publica 2 horários → aluno pega um → some da lista do outro aluno; aula aparece nas duas agendas;
   professor é avisado; tentar pegar horário que bate com outra aula e horário em menos de 60 min (deve recusar).
6. **Painel (`/admin`):** entra com a chave; indicadores carregam; abrir um perfil; bloquear e liberar; excluir só com o código digitado.
7. **Compatibilidade:** abrir o app anterior (cache antigo) com o servidor novo: tarefas, aulas e agenda seguem funcionando.
8. **Telas:** celular estreito e tela larga; modo escuro; textos em português.

## Guardrails de segurança (10/11/2026)
- **Cabeçalhos (vercel.json):** `Strict-Transport-Security` e `Content-Security-Policy-Report-Only` (só relata; não bloqueia). Testado localmente **aplicando** a política: app, abas e som (WASM/worker) funcionam sem violações. Para passar a bloquear, trocar o nome do cabeçalho para `Content-Security-Policy` depois de ver o console de produção sem avisos.
- **API:** código só aceito como texto (lista/objeto não viram código); `api/guardrails.test.js` cobre corpo ausente/gigante/malformado, `__proto__`, ids hostis, apelido com caracteres invisíveis, segredo/hash nunca na resposta, erro sem rastro interno, chave do painel só no cabeçalho.
- **App:** "Pegar horário" trava contra toque duplo; apagar horário livre pede confirmação. Já existiam confirmações para excluir aluno, desvincular professor, apagar tudo e vincular por convite/QR.
- **Não alterado de propósito:** o painel ainda aceita `FEEDBACK_ADMIN_KEY` como alternativa à `ADMIN_KEY` (tirar agora poderia trancar o administrador para fora); trocar quando a `ADMIN_KEY` própria estiver configurada na Vercel.

## Relatórios de erro e aba Bugs (Pacote 2, 10/11/2026)
| Ação | Quem | Comandos do Redis |
|---|---|---|
| Relatório de erro novo ou repetido (`/api/errors`) | app | **~23** (medido em `api/errors.test.js`: novo 23, repetição 22); modo leve (bug com 200+ repetições) ~16 |
| Aba Bugs: lista (`bugs`) | admin | 3 + até 60 (um por bug examinado) + 2 por bug da página (até 25) ≈ **até ~115** |
| Detalhe de um bug (`bug`) | admin | 6 |
| Mudar status (`bug_status`) | admin | 2–4 |

**Proteções de custo:** o app envia o mesmo problema no máximo 1 vez a cada 10 min e até 20 por sessão; por aparelho 10/hora; teto global por dia `ERRORS_DAILY_CAP` (padrão **150** eventos ≈ 3,5 mil comandos no pior dia, ~20% do uso diário da cota gratuita); chave de desligar `ERRORS_DISABLED=1` (para tudo sem publicar). Por padrão o app só envia sozinho os erros **graves** (`APP-99`, falha ao abrir); os demais só se a pessoa escolher "Todos os erros" ou tocar em "Enviar relatório".
**Chaves novas no Redis (`er:*`):** `er:f:<fp>` (bug), `er:fd:<fp>` (aparelhos, HyperLogLog), `er:t:<fp>` (tendência por dia), `er:o:<fp>` (últimas 10 ocorrências), `er:idx` (índice por última vez), `er:rs` (resolvidos), `er:n` (anotações), `er:b` (versões vistas), `er:d:<dia>` (contadores do dia e por hora), `er:rl:*` e `er:cap:*` (limites, expiram sozinhas). **Limpeza pendente:** `er:f:*`/`er:t:*` de bugs antigos não expiram (cresce devagar; limpeza no Pacote 3).
