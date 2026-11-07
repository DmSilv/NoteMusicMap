# Tom e Tempo (nome provisório até checar as lojas)

Afinador, metrônomo, grade de entonação e registro de estudo, em português, sem login.
Foco em instrumentos de corda (violino, viola, violoncelo, contrabaixo, violão, cavaquinho, ukulele, bandolim).

## Estrutura
- `packages/afina_core` — núcleo em Dart puro, com testes (`dart test`): matemática de afinação
  (igual / pitagórico / justo, cordas em quintas puras), detector de pitch McLeod, motor do
  metrônomo por posição de amostra, grade de entonação e relatório de escala.
- `lib/audio` — microfone (`record`) e saída de áudio (`flutter_soloud`).
- `lib/ui` — telas: Afinador, Metrônomo, Grade, Estudo.

## Comandos (com o Flutter 3.47.9 no PATH)
```
cd packages/afina_core && dart test        # 85 testes de precisão
flutter analyze
flutter run -d web-server --web-port=8099  # abrir http://127.0.0.1:8099
```

## Decisões de precisão
- Lá4 fixo em `refA` por padrão em todos os sistemas (opção de ancorar na tônica).
- Desvio sempre medido contra o alvo do sistema escolhido, nunca só contra o temperado.
- Detector: erro < 0,5 cent em tons limpos de 41 a 1318 Hz (testado a 44,1 e 48 kHz).
- Metrônomo: tick i = i × período, sem deriva (testado por 10 min simulados).

## Pendências conhecidas
- Calibrar latência de saída e taxa de amostragem do microfone em aparelho real.
- Android: instalar cmdline-tools, aceitar licenças (`flutter doctor --android-licenses`) e NDK.
- iOS: precisa de Mac (ou build na nuvem) e conta Apple Developer.
- Nome, ícone e política de privacidade antes de publicar.

## Identidade e configurações
- **Nome:** Tom e Tempo (Tom = afinador e grade; Tempo = metrônomo). Verificar disponibilidade nas lojas antes de publicar.
- **Logo:** mostrador de afinador, com arco do azul (grave) ao laranja (agudo) pelo verde (afinado) e ponteiro branco. Fonte: `tools/make_icons.mjs`
  (`node tools/make_icons.mjs` regenera todos os ícones: web, Android, iOS e `assets/logo/logo.svg`).
- **Configurações (engrenagem):** aparência (auto/claro/escuro), afinação (Lá, instrumento, sistema, transposição, bemóis),
  microfone, metrônomo (som, volume, ajuste de sincronia), grade, estudo e permissões/privacidade.
- **Permissões declaradas:** Android `RECORD_AUDIO` e `WAKE_LOCK`; iOS `NSMicrophoneUsageDescription`.
- **Antes de publicar:** trocar o `applicationId`/bundle id (hoje `br.app.afina`) pelo definitivo e revisar a política de privacidade.

## Estudo: Pomodoro
Na aba Estudo há um timer de foco (25 min), pausa curta (5) e pausa longa (15 a cada 4 focos), todos ajustáveis.
O fim de cada fase toca um sininho suave (duas notas, volume baixo) e vibra no celular. Configuração, estado do timer e a
contagem de focos por dia ficam salvos no aparelho. O alarme exige o app aberto (notificações com o app fechado ficam para depois).

## Publicação (Vercel + GitHub)
- `vercel.json` + `scripts/vercel_build.sh`: a Vercel baixa o Flutter 3.47.9 (versão fixa) e roda `flutter build web --release`.
  Na Vercel: importar o repositório, **Framework Preset: Other** (o `vercel.json` já define build e pasta `build/web`).
- `.github/workflows/ci.yml`: a cada envio roda os testes do núcleo, a análise e o build web.
- O site precisa de HTTPS para o microfone funcionar (a Vercel já entrega).
- Antes de abrir o repositório ao público, escolher uma licença (hoje não há `LICENSE`: todos os direitos reservados).

## Escalas guiadas, pontuação e treinador
- **Escalas (estilo Flesch):** Grade › Escala. Tom, tipo (maior, menor natural/harmônica/melódica, pentatônica, cromática) e **1, 2 ou 3 oitavas**.
  O app guia nota por nota, subindo e descendo, e calcula a **taxa de acerto** (notas dentro da faixa de afinação).
- **Histórico:** cada exercício vira um registro (gráfico de evolução, média, melhor resultado e variação) na aba Estudo.
- **Treinador:** análise por regras, feita no aparelho (`practice_coach.dart`): viés por nota ("suas notas Mi estão ficando baixas"),
  subida × descida, registro agudo, cansaço, tendência. Opcional: copiar um resumo (só números) para colar numa IA de conversa.
  Não há chamada a nenhuma IA: nada sai do aparelho.

## Áudio no navegador (importante)
O motor de áudio (SoLoud) tem versão multi-thread que isola o som da interface. Ela só liga se o site enviar
`Cross-Origin-Opener-Policy: same-origin` e `Cross-Origin-Embedder-Policy: require-corp` (já em `vercel.json`).
Sem isso, qualquer travada da tela vira chiado. Medido: 97 de 185 janelas de som com saltos sem os cabeçalhos; 0 de 185 com eles.
Nos apps de Android e iOS o áudio já roda em thread própria, sem esse problema.
