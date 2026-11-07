# Notemusic

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
cd packages/afina_core && dart test        # 216 testes (precisão, ponteiro, troca de nota, escalas)
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
- **Nome:** Notemusic (afinador, metrônomo, grade de entonação e estudo). Verificar disponibilidade nas lojas antes de publicar.
- **Logo:** mostrador de afinador (arco verde, a cor de destaque do app) com uma nota musical branca no centro. Fonte: `tools/make_icons.mjs`
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

## Grade: ponteiro vivo e troca de nota calma
- **Cursor dentro do quadrado (estilo Tonemap):** o quadrado da nota que toca vira um afinador horizontal: fundo escuro, faixa do meio = zona
  afinada, faixas laterais na cor viva (azul = grave, verde = afinado, laranja = agudo) e uma linha clara que desliza para o lado grave ou agudo.
  Ao entrar na zona, a linha fica verde-menta e a zona acende. Código: `lib/ui/cell_gauge.dart`.
- **Aba Grade:** um teclado de uma oitava (naturais embaixo, sustenidos/bemóis em cima, como num piano) com teclas grandes; a oitava acompanha a
  nota que toca. O botão "Abrir grade em tela cheia" mostra várias oitavas de uma vez. Os ♯/♭ são desenhados à mão (`NoteLabel`), com o mesmo
  tamanho e altura em qualquer aparelho. Seletor de oitavas 0 a 8 com botões separados e um pontinho nas oitavas em que você já tocou.
- **Movimento fluido:** a linha é uma mola amortecida resolvida de forma exata (`NeedleSpring`, `packages/afina_core/lib/needle_spring.dart`),
  calculada a cada quadro da tela (60 fps ou mais) e independente da taxa de leituras do microfone; a cor sai da posição já suavizada.
  O desenho fica numa camada própria (`RepaintBoundary`) e o relógio só roda enquanto há movimento.
- **Troca de nota calma:** só o DESTAQUE (nome, ponteiro e quadrado aceso) passa por um filtro (`NoteDisplayFilter`): a nota nova precisa se
  manter um instante e a atual fica um tempo mínimo na tela; notas de passagem não aparecem. As cores da grade continuam registrando tudo.
  Ajuste em **Grade › Ajustes › Troca de nota** (Rápida, Normal, Calma).
- **Animações do topo:** o nome da nota troca em "camadas" (a antiga sobe e some, a nova entra do lado oposto), a cor segue o desvio quadro a
  quadro e o número da dica desliza em vez de piscar.

## Notas rápidas (violino)
O detector usa um perfil por instrumento (`DetectorProfile`): para o violino, janela de 2048 amostras, faixa a partir de ~157 Hz e uma leitura nova
a cada ~17 ms (antes 4096 amostras e ~35 ms). O estabilizador troca de nota assim que DUAS leituras seguidas concordam. Medido por simulação
(`packages/afina_core/test/fast_notes_test.dart`, escala ligada com vibrato e ruído): notas de 100 ms passaram de 53% para 100% de reconhecimento e a
latência caiu de ~125 ms para ~55 ms. No aparelho real ainda falta validar com o violino.

## Taxa de atualização (120 Hz)
- **Web:** o Flutter desenha a cada `requestAnimationFrame`, então acompanha a taxa da tela (120 Hz em telas de 120 Hz no Chrome do Android; o Safari do iPhone
  limita páginas web a 60 Hz). Nada a configurar; nos testes o app chegou a 120 quadros por segundo com custo médio de ~3 ms por quadro.
- **iOS (app):** a chave `CADisableMinimumFrameDurationOnPhone` já está no `Info.plist`, liberando 120 Hz nos iPhones ProMotion.
- **Android (app):** alguns aparelhos limitam apps a 60 Hz; para pedir a maior taxa, usar o pacote `flutter_displaymode` (`setHighRefreshRate`). Não incluído ainda.
- **Bateria:** o app só anima enquanto há movimento (os relógios param quando tudo assenta); a taxa maior só custa quando algo está mexendo.
- **Medir:** em builds de teste (`--dart-define=DEV_DEMO=true`) o `FrameMeter` escreve no console o intervalo e o custo por quadro.

## Escalas guiadas, pontuação e treinador
- **Escalas (estilo Flesch):** Grade › Escala. Tom, tipo (maior, menor natural/harmônica/melódica, pentatônica, cromática) e **1, 2 ou 3 oitavas**.
  O app guia nota por nota, subindo e descendo, e calcula a **taxa de acerto** (notas dentro da faixa de afinação).
- **Arpejos (família do sistema de Carl Flesch):** Grade › Escala › Arpejos. Tríades maior e menor em posição fundamental e nas duas inversões,
  7ª da dominante e 7ª diminuta, em 1, 2 e 3 oitavas, sobe e desce. A tônica escolhida é a raiz do acorde.
- **Seguir meu ritmo (padrão) × Esperar cada nota:** no primeiro, toque a escala sem parar; cada nota vale quando você passa para a próxima
  (ou cala), o desvio é a **mediana** do que foi ouvido e notas fora do lugar só geram um aviso leve ("Ainda não é Lá3: suba um pouco").
  No segundo, o app espera você segurar cada nota até a barra encher. Troca no cartão da escala ou durante o exercício.
- **Histórico:** cada exercício vira um registro (gráfico de evolução, média, melhor resultado e variação) na aba Estudo.
- **Treinador:** análise por regras, feita no aparelho (`practice_coach.dart`): viés por nota ("suas notas Mi estão ficando baixas"),
  subida × descida, registro agudo, cansaço, tendência. Opcional: copiar um resumo (só números) para colar numa IA de conversa.
  O treinador por regras roda no aparelho. Já a **análise por IA** (opcional, com consentimento) é descrita abaixo.

## Análise por IA (Gemini via Vercel)
Botão "Analisar com IA" no card Treinador. A resposta segue um formato didático (visão geral, o que os números mostram, causas prováveis, plano da semana e exercício para amanhã), mostrado com títulos e tópicos. O app envia só o resumo numérico a `POST /api/coach`; a função da Vercel (`api/coach.js`)
guarda a chave e chama o Gemini. Nada de áudio ou dados pessoais.
- **Chave:** variável de ambiente `geminiAPI` na Vercel (também aceita `GEMINI_API_KEY`). Nunca vai para o repositório nem para o app. Depois de criar/alterar, faça **Redeploy**.
- **Plano gratuito protegido:** intervalo mínimo por pessoa (20 s), 5 análises/dia por pessoa, teto global por minuto (8) e por dia (200). Ajustáveis (`AI_*`, veja `.env.example`).
- **Fila:** se o servidor estiver cheio (429), o app espera com contagem regressiva e tenta de novo sozinho (até 5 vezes, com variação aleatória); dá para cancelar.
- **Contadores:** em memória por padrão; para valores exatos entre instâncias, ligue o Upstash Redis (`UPSTASH_REDIS_REST_URL/TOKEN`).
- **Celular:** gere o app com `--dart-define=API_BASE=https://SEU-DOMINIO.vercel.app`.
- Testes da função: `node --test api/coach.test.js`.

## Áudio no navegador (importante)
O motor de áudio (SoLoud) tem versão multi-thread que isola o som da interface. Ela só liga se o site enviar
`Cross-Origin-Opener-Policy: same-origin` e `Cross-Origin-Embedder-Policy: require-corp` (já em `vercel.json`).
Sem isso, qualquer travada da tela vira chiado. Medido: 97 de 185 janelas de som com saltos sem os cabeçalhos; 0 de 185 com eles.
Nos apps de Android e iOS o áudio já roda em thread própria, sem esse problema.
