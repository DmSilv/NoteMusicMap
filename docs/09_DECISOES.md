# Decisões de projeto (e por quê)

Formato: **decisão**, o motivo, as alternativas descartadas e o que muda se um dia revisitar.

## D1. Sem cadastro e sem login
O dono decidiu manter o app **sem cadastro**; "o código mais alguma info, até dia e data que entrou, já ajuda bastante".
- *Motivo:* atrito zero para quem só quer afinar; menos dados pessoais para proteger.
- *Alternativas:* conta com e-mail/Google (descartada por enquanto).
- *Consequência:* o "usuário" do painel é um **perfil anônimo** (código + apelido); o administrador trabalha com índice de perfis (entrou em, última atividade, papel), não com contas. Apelido não é editável pelo admin.

## D2. Identidade = código público + segredo de 256 bits no aparelho
O servidor guarda só o hash do segredo; o código serve para ser encontrado, **não dá acesso**. Trocar de aparelho exige a *chave de recuperação*.

## D3. Local primeiro; servidor só para o que cruza entre pessoas
O app inteiro funciona offline. O professor guarda seus alunos no aparelho; o servidor leva aulas, tarefas, decisões, agenda e horários entre os dois lados.

## D4. Redis (Upstash REST), não Postgres
O planejamento inicial (`ARQUITETURA_PROFESSOR_ALUNO.md`) previa Postgres; o que foi construído usa **Redis** por ser simples, sem dependências, com plano gratuito e acesso por REST. Custo: 500 mil comandos/mês, por isso a disciplina de custo (D6).

## D5. Nenhuma dependência npm na API
Só módulos nativos do Node (`crypto`, `node:test`). Menos superfície de ataque, build sem instalação, testes sem rede.

## D6. Custo é requisito: contadores de novidade em vez de polling de lista
`rev` custa ~0 (o perfil já foi lido); listas só baixam quando um contador (`lr dr kr sr vr ar`) mudou. Toda ação nova mede e documenta seus comandos.

## D7. O professor é a fonte oficial do status das tarefas
O aluno só sinaliza "fiz". O professor valida ou devolve; "devolver" também derruba o "fiz" no servidor. O aluno vê o status oficial (validada / aguardando / refazer).

## D8. Horário livre: o aluno pega e confirma na hora, sem aprovação
Decisão do dono: "o professor deixa os horários pré-definidos para os alunos pegarem e pode alterar horário dos alunos — mais controle". Primeiro que pegar leva (`HSETNX`). O professor mantém controle total (mover/cancelar) depois.

## D9. Núcleo em Dart puro, tela fina
Toda regra que merece teste vive em `afina_core` (sem Flutter, sem `dart:io`), com relógio por parâmetro. Motivo: `flutter test` não roda no ambiente de desenvolvimento; `dart test` roda rápido em qualquer lugar.

## D10. API retrocompatível, sempre
Há usuários reais com versões antigas em cache (PWA). Só se **acrescenta** ação/campo; nunca se muda o significado.

## D11. Visões Aluno | Professor no Meu espaço, um destino por tela
Quem é professor também pode ser aluno de outra pessoa. As visões são separadas e testadas para **nenhum destino aparecer duas vezes** e **nenhum destino do outro papel aparecer** (`hub_view.dart`). O destaque age sobre a aula; não duplica a agenda.

## D12. Erros: só a falha ao abrir derruba para tela cheia
Erros inesperados depois disso viram aviso + registro, para um erro pequeno nunca esconder o app inteiro. Código curto `E-XXXX` para a pessoa citar.

## D13. Relatórios de erro: automáticos só para os graves
Escolha do dono/recomendação: "Só os graves" por padrão, com "Todos" e "Nunca" nos Ajustes e envio manual sempre disponível. Dados sempre higienizados (no app e no servidor). Chave `ERRORS_DISABLED` desliga tudo sem publicar.

## D14. Reabertura de bug só por versão publicada depois da correção
Evita falso alarme de aparelhos com versão antiga em cache; usa a "primeira vez que a versão foi vista" (`er:b`).

## D15. CSP: primeiro "somente relatório", depois bloqueio (feito em 11/2026, depois de testar a política aplicada)
O app carrega CanvasKit/WASM e workers; uma política errada o derrubaria. Testada localmente aplicando a política sem violações; passa a bloquear depois de conferir produção.

## D16. Painel aceita `FEEDBACK_ADMIN_KEY` como alternativa à `ADMIN_KEY`
Tirar agora poderia trancar o administrador para fora. Remover quando a `ADMIN_KEY` própria estiver configurada.

## D17. Testes da API fora do deploy
Cada arquivo em `api/` conta como função (limite 12 no Hobby). `.vercelignore` exclui `api/*.test.js`. (Aprendido na prática: deploys falharam por isso.)

## D18. Contagem de aparelhos é aproximada (HyperLogLog)
Erro ≈ 1%, custo mínimo. O painel diz isso. Perfis são contados de forma exata (índice).

## D19. Publicação só com "sim" explícito, um pacote por vez
Há usuários reais. Cada pacote: testes + conferência na tela + custo + impacto + rollback, e então o "sim".

## D20. Documentação gerada do código onde possível
Arquivos, API, chaves, erros e ambiente saem de `scripts/gen_docs.js`; `--check` falha se estiverem velhos. A parte escrita à mão explica o **porquê**.

## D21. Recursos novos saem aos poucos, por chaves no painel
Cada novidade nasce desligada e é liberada por código de perfil, depois por porcentagem e, por fim, para todos; dá para desligar na hora sem publicar. O servidor é quem decide (o app só esconde). Substitui a variável `LIBRARY_TESTERS`, que vira o ponto de partida do recurso `acervo`. Plano em `docs/PLANO_AULA_ONLINE_AGENDA_ADMIN.md`.

## D22. Tutorial nunca é obrigatório
O guia de uso é sempre opcional (convite no cartão "Comece por aqui" e botão "?"), com "Pular" em todo passo, e só vive no aparelho. Um mecanismo único (`runTour`) serve a todos os tutoriais; cada tutorial é só uma lista de passos.

## D-email. E-mail opcional e sem senha para recuperar a conta
- *Contexto:* o perfil nasce sem cadastro (D1) e só a chave de recuperação ou o código de suporte do painel levavam a conta a outro aparelho. Para o professor, perder o celular era perder a lista de alunos.
- *Decisão:* e-mail **opcional**, **sem senha**: código de 6 dígitos enviado ao e-mail (prova de posse), em `/api/account`. O cadastro instantâneo continua; o e-mail é uma camada de recuperação que a pessoa liga se quiser.
- *Alternativas descartadas:* login com e-mail e senha (guardar senhas, redefinir, bloquear tentativas: mais risco e suporte para o mesmo ganho); login com Google (dependência e dados de terceiros).
- *Consequências:* o servidor passa a guardar um dado pessoal (hash do e-mail, mascarado para exibir); precisa de um provedor de e-mail com domínio verificado (`MAIL_*`); 1 função a mais na Vercel (10 de 12). Quem controla o e-mail controla a conta, então o código é curto, de uso único e com tentativas limitadas.

## D-chave25. Chave de recuperação curta (25 caracteres), verificada no servidor
- *Contexto:* a chave antiga (~100 caracteres) é a identidade inteira em texto: ninguém consegue anotá-la, e a maioria não guarda.
- *Decisão:* uma chave aleatória de 25 símbolos (125 bits) que o servidor guarda só como hash; digitá-la num aparelho novo troca o segredo do perfil. A antiga continua valendo; a nova é a principal. Funciona sem e-mail e sem domínio.
- *Consequências:* deixa de ser autossuficiente (precisa do servidor e do perfil registrado, o que acontece quando a pessoa gera a chave); o aparelho antigo perde o acesso ao usá-la; quem tem a chave assume a conta.

## D-multiaparelho. Até 5 aparelhos por conta, todos iguais (sem aparelho principal)
- *Contexto:* a mesma conta passou a abrir em vários aparelhos. Foi considerado um modelo "aparelho principal", como no WhatsApp Web (só o principal adiciona e tira os outros).
- *Decisão (17/11/2026, Daniel):* **todos os aparelhos são iguais**: qualquer um adiciona ou tira outro, até **5 ao mesmo tempo**. O limite aparece à vista (Minha conta › Aparelhos mostra uma bolinha por vaga e quantas faltam; a tela de entrar numa conta e o aviso de conta cheia dizem o mesmo). Perdeu o aparelho: entra num novo pela chave de 25 caracteres ou pelo e-mail e tira o antigo da lista.
- *Alternativa descartada:* aparelho principal (um dono que manda nos outros): mais regras, e perder o principal exigiria um caminho de recuperação a mais; o ganho de segurança não compensou agora. Pode voltar se houver abuso (conta compartilhada com estranhos).
