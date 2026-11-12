# Plano dos próximos passos (a partir de novembro/2026)

Ponto de partida: tudo da entrega de novembro está publicado (ver `ENTREGA_NOVEMBRO.md`). Regras de sempre: testar, mostrar no
navegador (390×844), API compatível com apps antigos, custo baixo (Upstash 500 mil comandos/mês, Vercel Hobby, até 12 funções),
recurso novo atrás de chave e só publicar com o "Sim, publicar".

## Fase 0: fechar a entrega (esta semana, sem código novo)
| Passo | Quem | Pronto quando |
|---|---|---|
| Conferir o CI e o CodeQL no GitHub (primeira execução) | você olha, eu corrijo se ficar vermelho | os dois verdes |
| Ligar *Secret scanning*, *Push protection* e proteger o `main` | você (GitHub › Settings) | ligado |
| Painel › Recursos: confirmar os três cartões (acervo, aula online, lembrete escolhido) e o acervo do Vinícius | você | ok |
| Liberar **Aula online** só para o Vinícius (com os alunos dele) e usar de verdade por 1 semana | você + Vinícius | 3 aulas online com link, sem erro no painel |
| Testar em **celular real** (Android e iPhone): vibração, abrir link da sala, tutorial, folha de sucesso | você | lista de problemas (se houver) |
| Conferir se os **lembretes** (QStash e VAPID) estão ativos na Vercel | você; eu explico o que olhar | cartão da agenda deixa de dizer "Notificações ainda não disponíveis" |
| Configurar `LIBRARY_TESTERS` → já migrou para a aba Recursos; tirar a variável quando não precisar mais | você | variável removida |

## Fase 1: confiança e qualidade (2 a 3 semanas)
Objetivo: publicar sem medo. Hoje só o núcleo e a API têm teste automático forte.
1. **Teste de fumaça no CI (feito):** `scripts/smoke.js --web` repete marcar aula, pegar horário (dois ao mesmo tempo), passar tarefa, aula online, remarcar, trocar e pausar,
   e abre o app num Chrome sem janela. Roda a cada envio. Não clica nos botões do Flutter: isso fica para o item 2.
2. **Teste de tela do Flutter no CI (parcial, feito):** `node scripts/ui_tests.js` testa o modal de sucesso e o tutorial guiado (11 testes) e roda no CI. Falta o formulário de aula
   e o cartão Comece por aqui: dependem do `AppState` (áudio nativo). Caminho: separar o que a tela precisa do `AppState` por uma interface pequena. *Pronto quando* essas telas tiverem teste.
3. **Textos do Flutter em português (feito):** `flutter_localizations` com `pt-BR` (`lib/ui/app_locale.dart`). Seletores de data e hora, "OK"/"Cancelar" e nomes de mês saem em português; conferido no navegador e com 4 testes.
   Custo: +140 KB compactado (+11,5%) no download do app web, porque o Flutter embute os textos de todos os idiomas.
4. **Alerta no painel e no celular do admin:** aviso (push) para erro crítico, pico de cadastros e lembrete falhando, para você não precisar
   olhar o painel. Já existe push de bug grave; ampliar os gatilhos.
5. **Métricas de sucesso definidas por escrito** (ver Fase 3) e mostradas no painel.

## Fase 2: o dia a dia do professor (1 a 2 meses)
Ordem por valor para quem dá aula, cada item atrás de uma chave em `Recursos`:
1. **Pedido de troca do aluno:** o aluno pede para trocar uma aula, o professor aceita ou recusa, e a agenda dos dois muda sozinha. Tira a
   conversa do WhatsApp. Reaproveita remarcar/trocar (já existem e são aplicados de uma vez).
2. **Falta e reposição:** marcar "aluno faltou", gerar uma reposição (horário livre dedicado) e manter o histórico por aluno.
3. **Visão de semana em grade** na agenda (hoje é lista) com toque longo para mover uma aula.
4. **Lembrete com o link:** o aviso da aula online leva o botão "Entrar". Depende da Fase 0 (lembretes ativos). O **tempo do aviso já é escolhido pelo professor** (feito, chave `lembrete_escolha`).
5. **Tutorial do aluno** e dicas de primeiro uso (código, vincular, pegar horário), no mesmo mecanismo do tutorial do professor.
6. **Acervo para todos os professores:** abrir pela chave em etapas (você → Vinícius → 10% → todos), depois de a revisão jurídica sair (Fase 4).

## Fase 3: crescer com segurança (contínuo)
- **Metas e acompanhamento**, olhando o funil de Ativação do painel: % de perfis que vinculam, marcam a 1ª aula e passam a 1ª tarefa; retenção
  em 7 e 30 dias; professores que usam a agenda toda semana. Escolher 3 números e revisar toda semana.
- **Divulgação:** continuar os vídeos curtos (YouTube e Instagram) com o link `/yt` e `/ig`; o painel Visitantes mede o efeito. Próximos
  roteiros: aula online, "Comece por aqui", remarcar e pausar aulas.
- **Custo:** olhar a aba Custos toda semana; se passar de 60% do limite, medir qual ação gasta mais antes de crescer. Plano B de custo:
  consultas mais espaçadas e contadores em lote.
- **Suporte:** usar a ficha "Acompanhar" e "Comparar agendas"; anotar os problemas mais comuns para virar melhoria do app.

## Fase 4: lojas e jurídico (adiada: o foco agora são os ajustes do app)
Meta: Google Play (conta de desenvolvedor já existe). Passos, em ordem:
1. Conferir o `AndroidManifest` de release (permissão de internet), `applicationId` definitivo e chave de assinatura (upload keystore guardada com segurança).
2. **Página pública de política de privacidade** (a do app serve de base) e a ficha da loja (textos, capturas, ícone).
3. **Teste fechado** com professores e alunos reais por 2 semanas (a Play exige para contas novas), com o canal de feedback do app.
4. Só então a publicação aberta; iOS depois, se valer o custo da conta e do Mac.
5. **Revisão por advogado** do desenho do acervo (links, declaração de direitos, denúncia) e da política de privacidade, que agora inclui o suporte
   poder ver agenda e tarefas.
Antes das lojas: privacidade e termos atualizados, link da aula tratado como dado do usuário e política de retenção descrita.

## Dívida técnica e cuidados (fazer junto, sem pressa)
- Manter `AppState` enxuto: partes novas em arquivos próprios (como `meeting_link.dart` e `tour/`), sem crescer o arquivo principal.
- Revisar o limite de 12 funções da Vercel antes de qualquer endpoint novo (hoje 8); novas ações entram nos endpoints existentes.
- Revisar o service worker e o cache a cada versão grande (já causou ícones sumindo uma vez).
- Rodar `npm audit`/Dependabot semanalmente e atender os pull requests de segurança.

## Decisões suas para começar
1. A **Fase 0 primeiro** (recomendo) e, em paralelo, a Fase 1 item 1 (teste de fumaça), que dá mais segurança para tudo que vem depois?
2. Qual da Fase 2 vem primeiro: **pedido de troca do aluno** (recomendo) ou **falta e reposição**?
3. Há professores além do Vinícius que podem testar a aula online agora?
4. Quando quer começar a preparação da Play Store? (recomendo só depois da Fase 1)
