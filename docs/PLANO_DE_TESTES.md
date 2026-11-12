# Plano de testes

Objetivo: saber, **antes** de os usuários sentirem, se o app aguenta crescer, se continua certo a cada publicação e quanto custa manter.
Legenda de situação: **feito** (já roda), **fazer** (planejado), **você** (precisa do seu celular, conta ou decisão).

## 1. Camadas de teste
| Camada | O que garante | Situação |
|---|---|---|
| Testes do núcleo (`dart test`) | Afinação, metrônomo, agenda, remarcar/trocar/pausar, link da aula, checklist (571 testes) | **feito** (CI) |
| Testes da API (`node --test api/*.test.js`) | Vínculo, agenda, horários livres, acervo, chaves de recursos, aula online, funil, custos, proteções (283 testes) | **feito** (CI) |
| Análise do Flutter, conferência de documentação e de texto | Código sem avisos, docs em dia | **feito** (CI) |
| Varredura de segurança (CodeQL) e Dependabot | Falhas comuns e pacotes com correção de segurança | **feito** (GitHub) |
| Simulação de carga lógica (`node scripts/simulate_load.js`) | Quantos comandos do Redis e chamadas de função cada usuário gasta | **feito** (manual; ver seção 3) |
| Teste de fumaça no navegador | Os fluxos principais abrem, clicam e terminam certo | **fazer** (seção 4) |
| Teste de carga real em ambiente de teste | Velocidade e erros com centenas de usuários ao mesmo tempo | **fazer** (seção 3) |
| Celulares de verdade | Vibração, microfone, abrir link da sala, instalar, notificações | **você** (seção 5) |
| Teste com professores e alunos reais | Se entendem e conseguem usar sem ajuda | **você** (seção 6) |

## 2. Antes de cada publicação (checklist curto)
1. CI verde (análise, núcleo, API, docs, build web).
2. Conferir no navegador em 390×844 (e 360) as telas que mudaram, com o recurso ligado **e desligado**.
3. Rodar `node scripts/simulate_load.js 300` e comparar com a linha de base (seção 3): se os comandos por usuário subirem mais de 20%, investigar antes de publicar.
4. Revisar custo: aba Custos do painel (comandos do mês e projeção).
5. Publicar só com o "Sim, publicar"; recurso novo entra por chave (Recursos), nunca para todos de uma vez.
6. Depois: olhar bugs e erros do painel por 24 h; se piorar, **Desligado** na chave ou `git revert`.

## 3. Carga: o que acontece com 100, 1.000 ou 10.000 usuários
**3.1 Simulação lógica (pronta).** Roda os handlers de verdade com usuários fictícios por um mês (15% professores, 35% dos usuários ativos por dia,
visita de ~12 min) e conta comandos do Redis e chamadas de função. Linha de base (300 usuários, 12/11/2026): **387 comandos, 136 chamadas de função e
3,4 lembretes por usuário ativo por mês.** Esses números alimentam a aba Custos › Contas. Limite: não mede velocidade de rede nem os limites reais dos serviços.

**3.2 Carga real (fazer).** Ferramenta: k6 (gratuita). Ambiente: **nunca a produção.** Usar um deploy de pré-visualização da Vercel e um banco Upstash
**separado** (grátis), com `ADMIN_KEY` própria.
| Cenário | Usuários simultâneos | Duração | Critério de aprovação |
|---|---|---|---|
| Aquecimento | 50 | 5 min | 0 erros 5xx |
| Dia normal | 200 | 15 min | p95 abaixo de 800 ms, erros abaixo de 1% |
| Pico (aula começando) | 1.000 chegando em 2 min | 10 min | p95 abaixo de 1,5 s, erros abaixo de 2%, sem perder dados |
| Todos pegam o mesmo horário livre | 100 no mesmo horário | 1 min | exatamente 1 aluno leva (regra "o primeiro leva") |
| Limites anti-abuso | 1 usuário martelando | 2 min | recebe 429, os outros não sentem |
Durante o teste, olhar no Upstash (comandos e latência) e na Vercel (chamadas, erros, tempo). **Custo do teste:** ~400 mil comandos por rodada de 1.000 usuários: cabe no grátis de um banco de teste.

**3.3 O que o relatório de custos mostra hoje.** Em Painel › Custos › Contas: gasto atual, cenários de 100/1.000/5.000/10.000 e o número que você escolher, em dólar e em reais, com avisos
de limite (banco, lembretes, funções da Vercel, uso comercial). Resultado da simulação com os preços de tabela de 12/11/2026:
| Usuários ativos/mês | Comandos | Chamadas de função | Total aproximado |
|---|---|---|---|
| 100 | 38.700 | 13.600 | US$ 0 (tudo grátis) |
| 1.000 | 387.000 | 136.000 | US$ 0, com aviso: a Vercel Hobby pode bloquear acima de 100 mil chamadas (as fontes divergem) |
| 5.000 | 1,9 milhão | 680 mil | ~US$ 3 (banco pago em centavos) |
| 10.000 | 3,9 milhões | 1,36 milhão | ~US$ 27 (Vercel Pro US$ 20 + banco ~US$ 7) |
**Atenção:** se o app gerar receita (anúncios ou assinatura), o plano Hobby da Vercel não vale (só uso não comercial): passa a ser Pro (US$ 20/mês) já com poucos usuários.

## 4. Teste de fumaça (fazer)
Reaproveitar o app de demonstração usado nos vídeos (`video8_work/agenda_demo.js`) e o Chrome sem tela, a cada envio ao GitHub:
marcar aula e conferir na agenda; pegar horário (aluno) e ver na agenda do professor; passar tarefa e ver "Enviada ao aluno"; aula online (chave ligada) com link e botão Entrar;
remarcar só uma aula; trocar horários; Comece por aqui. **Pronto quando** falha sozinho se um deles quebrar. Obs.: gravar com `SC=1` (modo sem atraso do Chrome).

## 5. Celulares de verdade (você, 30 minutos)
| Aparelho | Verificar |
|---|---|
| Android (Chrome) | instalar na tela inicial; microfone no afinador; vibração (batida leve ao dar certo); notificação de lembrete; abrir link do Meet |
| iPhone (Safari) | instalar pelo Compartilhar › Adicionar à Tela de Início (notificações só assim); microfone; abrir link da sala |
| Computador | todas as telas, painel admin, tela cheia da grade |
Anotar: modelo, versão do sistema, o que falhou e uma captura de tela. Mandar para eu corrigir.

## 6. Teste com pessoas reais (você + Vinícius)
Roteiro de 15 minutos com 3 professores e 3 alunos, sem ajuda: (1) abrir o app e achar o "Comece por aqui"; (2) vincular um aluno; (3) marcar uma aula toda semana; (4) publicar um horário livre online;
(5) aluno pega o horário e entra na aula; (6) remarcar uma aula. Medir: tempo, onde travou, o que perguntou. **Pronto quando** 5 de 6 concluem sem ajuda.

## 7. Segurança (contínuo)
CodeQL e Dependabot no GitHub; testes de proteção (`api/guardrails.test.js`: sem `eval`, painel sem `confirm()`, limites por hora, entradas inválidas); chaves de recurso decididas no servidor;
admin com limite de tentativas. A fazer: revisão por advogado do acervo e da política de privacidade; teste de invasão básico (tentar ler dados de outro perfil, estourar limites) antes da loja.

## 8. Acessibilidade e usabilidade (fazer)
Contraste, tamanho de fonte com o texto do sistema grande, toque mínimo de 44 px, leitura por leitor de tela nas telas principais (Meu espaço, Agenda, formulário de aula).

## 9. Calendário sugerido
| Semana | Testes |
|---|---|
| 1 | Seção 2 em toda publicação; celulares reais (seção 5); liberar aula online para o Vinícius |
| 2 | Teste de fumaça no CI (seção 4); roteiro com pessoas reais (seção 6) |
| 3 | Carga real em ambiente de teste (seção 3.2); ajustar o que aparecer |
| 4 | Acessibilidade (seção 8); revisar custo com dados reais (Contas com "Real") |
