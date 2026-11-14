# Plano: primeiro acesso e retenção (novembro/2026)

Problema: as publicações trazem gente ao app, mas quase ninguém fica. O app tem ferramentas boas (afinador, escalas com partitura e
dedilhado do Flesch, metrônomo, grade, agenda), mas a pessoa precisa mexer muito para descobrir que elas existem, e nada diz, logo
na entrada, **qual é a ideia do app**.

Regras de sempre: testar, mostrar no navegador (390×844), custo baixo (Upstash 500 mil comandos/mês), API compatível, texto novo com
`tr()` e inglês, e só publicar com o "Sim, publicar".

## 1. Diagnóstico do que a pessoa vê hoje (conferido no app, conta nova)

| Momento | O que acontece | Problema |
|---|---|---|
| 1ª tela | Abre em **Meu espaço**, com o cartão "Vincule seu professor" | Quem veio de uma publicação quase sempre estuda sozinho: cai numa tela que não explica o app |
| Logo em seguida | Caixa **"Vamos deixar tudo pronto"**: microfone, vibração, internet | Pede permissões **antes de mostrar qualquer valor** |
| Afinador | "Cordas soltas / Cromático / Pedal", "Desvio", "Alvo", "Toque no microfone para começar" | Vocabulário técnico; **nada acontece sozinho**, é preciso tocar no microfone |
| Escalas e Grade | Telas ricas (partitura, dedilhado, grade de notas) | O melhor do app fica atrás de 2 a 4 toques e de configurações; ninguém diz que existe |
| Mensagem | Em nenhum lugar há uma frase de **promessa** ("o app ouve você e diz se está certo") | A missão não aparece |
| Medição | O painel mostra retorno D1/D7/D30 e ativação, **mas a ativação é de professor/aluno** (vincular, marcar aula...) | Falta medir o valor do músico solo: afinou uma nota, tocou uma escala, usou o metrônomo |

## 2. O que a pesquisa diz (e o quanto confiar)

- **Referência de retenção em apps móveis:** mediana perto de **26% no dia 1, 13% no dia 7 e 7% no dia 30** (Adjust 2024); outros
  levantamentos dão 25% / 8% / 4%. Bons apps ficam em 30 a 40% no dia 1 e 10 a 15% no dia 7. *Confiança: média (blogs de fornecedores);
  use como ordem de grandeza, não como meta rígida.*
- **Tempo até o valor:** quanto mais rápido a pessoa chega ao "momento de entender" (aha), mais gente volta no dia seguinte. A regra
  prática: escolher **uma primeira ação** que prevê o retorno e fazer da 1ª sessão o caminho até ela; adiar cadastro, permissões e
  pedidos para depois dela. *Confiança: média; é consenso de várias fontes, sem estudo independente.*
- **Experimentar antes de se comprometer (Duolingo):** deixar fazer uma lição e ver o que há antes de pedir cadastro aumentou métricas;
  um dos testes (cadastro mais para trás) teria dado cerca de **+20% de usuários ativos por dia**, e refinamentos +8,2%. *Confiança:
  baixa a média; vem de entrevista, não de dado publicado.*
- **Apps de música:** Simply Piano e semelhantes levam a pessoa a **tocar uma música reconhecível em poucos minutos**. Um estudo de caso
  do JoyTunes (Simply Guitar) disse que mudar a entrada dobrou quem toca a 1ª música e subiu a retenção de 1 semana e 1 mês em cerca
  de **25%**. *Confiança: baixa (caso de um fornecedor de análise, números próprios).*
- **Permissões:** pedir o microfone **no contexto** ("toque uma corda; para isso preciso ouvir") com uma tela de explicação antes do
  pedido do sistema funciona melhor que pedir tudo na abertura. O Babbel não pede o microfone na lição inicial. Os aumentos citados
  (28% a 30%) vêm de blogs e não têm estudo por trás. *Confiança: alta na direção, baixa nos números.*
- **Ajuda na hora certa:** o GuitarTuna usa um aviso curto na primeira vez que a pessoa entra num modo, em vez de um tutorial longo.
- **Sequências de dias (streaks) e lembretes:** funcionam onde existe um ciclo diário real (aprender, treinar), mas **não criam hábito
  sozinhos**; ajudam mais quando perdoam falhas ("congelar" um dia) e quando a pessoa retoma depois de parar. *Confiança: baixa;
  não achei estudo controlado.*

O que a pesquisa **não** resolve: o número certo para o Notemusic. Com pouco tráfego, o caminho é medir o nosso próprio D1/D7 por
publicação (o link já aceita `?o=ig`, `?o=yt`) e comparar antes e depois.

## 3. A ideia central

**Prometer em uma frase, provar em 30 segundos.**

> "Toque uma nota e veja, na hora, se está afinada."

Tudo na primeira sessão leva a **um momento**: a pessoa toca uma corda, a agulha se mexe e aparece **AFINADA!**. Esse é o "aha"
do app. O resto (escalas, partitura, metrônomo, professor) vem depois, como próximo passo sugerido, não como menu.

## 4. Apresentação breve (4 telas + a conquista, 20 a 30 segundos, sempre com "Pular")

Protótipo navegável (versão 2): [prototipo_apresentacao/index.html](prototipo_apresentacao/index.html). Abre no navegador, em tema claro
e escuro, de 320 a 430 px de largura; é um roteiro, não o app. Para ver pelo servidor local: `node -e "require('http').createServer((q,r)=>{r.setHeader('content-type','text/html;charset=utf-8');r.end(require('fs').readFileSync('docs/prototipo_apresentacao/index.html'))}).listen(8150)"`.

| # | Tela | Texto | O que mostra |
|---|---|---|---|
| 1 | Promessa | **Seu instrumento afinado e estudando de verdade.** O Notemusic ouve você tocar e mostra na hora se cada nota está certa. Sem cadastro e sem custo. | **O próprio afinador**, não uma ilustração: a agulha sobe de "Um pouco baixa" a "Afinada!" em ciclo (a missão em 4 segundos) |
| 2 | O que tem aqui | **Tudo para o seu estudo, num só lugar.** Comece pelo afinador e vá para as escalas quando quiser. | Três pedaços reais do app: partitura com dedo e posição ("corda Sol (IV), 2ª posição"), metrônomo e evolução |
| 3 | Personalizar | **Dois toques para deixar do seu jeito.** Instrumento (Violino, Viola, Violoncelo, Violão, Outro) e "Como você estuda?" (Sozinho, Tenho professor, Sou professor) | Ícones de linha e duas escolhas de um toque; **Sozinho abre o Afinador**, as outras abrem o Meu espaço |
| 4 | Primeira ação | **Toque uma corda e veja a nota aparecer.** Pede o microfone **aqui**, com a frase de privacidade: o som é analisado no aparelho e descartado; nada é gravado nem enviado | Violino com a corda Lá vibrando, ondas e o "Lá4"; botão **Permitir o microfone e afinar** e "Agora não" |
| 5 | Primeira conquista | **Primeira nota afinada!** (só aparece depois do microfone) | Anel que fecha em volta do "Lá4" e o cartão **"Seu primeiro passo, 1 de 3"** (✓ afinar uma corda · tocar a primeira escala · estudar 5 min com o metrônomo) |

Princípios aplicados (da pesquisa): mostrar **pedaços reais do produto** em vez de ilustração genérica; no máximo 3 a 4 telas antes do
valor; **"Pular" sempre à vista** e barra de progresso segmentada; permissão pedida **depois** de mostrar o valor e com a
explicação de privacidade no mesmo lugar; botão principal único, com verbo ("Permitir o microfone e afinar"); texto curto (título
de até 2 linhas, até em 320 px); movimento leve que respeita "reduzir movimento"; toque mínimo de 44 px e contraste conferido nos
dois temas. A tela 5 existe porque o primeiro "aha" precisa de **reforço e de um próximo passo**, senão a pessoa acerta a nota e fecha o app.

Depois da tela 4 a pessoa cai no **Afinador já ouvindo**, com a agulha pronta. Quando acertar a primeira nota, o app comemora (já
existe o "momento de sucesso") e mostra o cartão de **próximo passo** (tocar a primeira escala).

## 5. Plano em fases

| Fase | O que entra | Esforço | Como saber que deu certo |
|---|---|---|---|
| **A. Entrada** (primeiro) | As 4 telas e a conquista acima; **home depende da resposta** (sozinho abre o Afinador); microfone pedido só na tela 4 (a caixa "Vamos deixar tudo pronto" some); "Pular" sempre visível; textos em `tr()` e inglês | 2 a 3 dias | Mais gente chega à 1ª nota afinada na 1ª sessão |
| **B. Primeiros passos** | Cartão **"Seu primeiro passo"** no Afinador e no Meu espaço, como o "Comece por aqui" do professor: ✓ afinar uma corda · ✓ tocar a primeira escala (Sol maior, 1 oitava, já escolhida, um botão **Tocar agora**) · ✓ marcar 5 min de estudo; trocar o jargão por rótulos claros ("Cordas soltas" → "Afinar as cordas"; "Pedal" some do primeiro plano); aviso curto na 1ª vez que abrir Escalas e Grade; o afinador começa a ouvir sozinho depois da permissão | 3 a 5 dias | Mais gente toca uma escala na 1ª semana |
| **C. Voltar amanhã** | **Meta do dia** simples (5 min) e **dias seguidos** com perdão de 1 dia; lembrete combinado com a pessoa (o push já existe; falta ligar o QStash); **resumo da semana** em Evolução; convite para **instalar o app** só na 2ª sessão; convite para **vincular o professor** só depois da 1ª conquista | 1 a 2 semanas | D1 e D7 sobem |
| **D. Medir** (começa junto com A) | Eventos de **primeira vez**: abriu, escolheu instrumento, liberou o microfone, **1ª nota afinada** (o aha), 1ª escala iniciada e concluída, voltou no dia 1 e no 7. Novo cartão no painel: **"Ativação do músico solo"**, separado por origem do link (`?o=`) | 1 a 2 dias | Dá para comparar publicações e versões |

Custo: cada evento de primeira vez vira **um contador agregado**, no máximo uns 6 comandos por aparelho novo, nada por uso. Cabe
folgado no plano (500 mil comandos/mês). Nada de rastreamento por pessoa além do que o painel já mostra.

## 6. Como testar sem tráfego grande

1. **Antes e depois:** anotar D1, D7 e "chegou à 1ª nota afinada" das duas últimas semanas (já no painel, menos o aha) e comparar
   com as duas semanas depois da fase A.
2. **Duas publicações, dois links:** `?o=ig1` (entrada nova) contra `?o=ig2` (entrada antiga, atrás de um interruptor no painel
   Recursos) para o mesmo público.
3. **Quem testa:** 3 a 5 pessoas que **nunca viram o app** (uma publicação, ou um amigo músico), com o celular, falando em voz alta; o
   que não entenderem em 30 segundos é o que se corrige primeiro.

## 7. Decisões que dependem de você

1. A pergunta "Como você estuda?" pode **ser pulada**? (sugestão: sim, e o padrão é "Sozinho").
2. O texto "Sem cadastro, sem custo" na tela 1 está certo hoje? (o app não cobra e o cadastro só aparece no vínculo com professor)
3. Instrumentos da tela 3: só os que o app afina bem hoje, ou todos os que ele já lista?
4. Quem responde "Tenho professor" ou "Sou professor" vê o **Meu espaço** primeiro (como hoje). Concorda?

## 8. Fontes consultadas

- [Mobile App User Retention: A 2026 Playbook (RapidNative)](https://www.rapidnative.com/blogs/mobile-app-user-retention)
- [App retention strategies (Userpilot)](https://userpilot.com/blog/app-retention-strategies/) e [Mobile app retention (Userpilot)](https://userpilot.com/blog/mobile-app-retention/)
- [App onboarding best practices (MWM)](https://mwm.ai/guides/app-onboarding-best-practices)
- [How Duolingo A/B tested delayed sign-ups (Taplytics)](https://taplytics.com/blog/duolingo-ab-test-onboarding) e [The tenets of A/B testing from Duolingo's growth hacker (First Round Review)](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/)
- [Duolingo's user onboarding (Appcues GoodUX)](https://goodux.appcues.com/blog/duolingo-user-onboarding)
- [Growth Design Dissections: Yousician's Onboarding](https://medium.com/design-bootcamp/growth-design-dissections-1-yousicians-onboarding-b043f2466f40)
- [JoyTunes case study (Appsee)](https://www.casestudies.com/company/appsee/case-study/joytunes-uses-appsee-to-improve-retention-usability-and-conversions)
- [Mobile permission priming (Appcues)](https://appcues.com/blog/mobile-permission-priming) e [Optimize permission requests (Superwall)](https://superwall.com/solutions/optimize-permission-requests-ask-at-the-right-time-and-you-shall-receive)
- [How we built the streak feature (WeWard)](https://www.wewardapp.com/blog/how-we-built-the-streak-feature-to-boost-user-retention-and-create-healthy-habits) e [Are streak features still spreading beyond Duolingo? (Lazyweb)](https://www.lazyweb.com/research/are-streaks-still-spreading-beyond-duolingo.md)
- [App Showcase: GuitarTuna (ScreensDesign)](https://screensdesign.com/showcase/guitartuna-tune-play-guitar)

A maior parte vem de blogs de fornecedores e de entrevistas; os números servem de ordem de grandeza. Nenhum substitui medir o app.
