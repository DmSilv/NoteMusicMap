# Notemusic: leia primeiro

Este é o ponto de partida da documentação. Se você vai dar manutenção, comece aqui e siga os links.

## O que é o app
**Notemusic** é um app em português, **sem cadastro e sem login**, para quem estuda música de corda (violino, viola, violoncelo, contrabaixo, violão, cavaquinho, ukulele, bandolim):
- **Afinador** (cordas soltas, cromático e *Pedal* com notas sustentadas), **metrônomo**, **grade de entonação** e exercícios de escala, **registro de estudo** (Pomodoro, cronômetro, "meu tempo").
- **Professor e aluno** (opcional, com "vínculo online"): o professor cadastra alunos, passa tarefas, valida o que o aluno fez, marca aulas (com lembrete, 15 minutos antes por padrão; o professor pode escolher) e publica **horários livres** para o aluno escolher.
- **Painel do administrador** (`/admin`): indicadores de uso, perfis, **bugs** e custos.

Roda no **navegador** (PWA instalável, hospedado na Vercel) e tem projetos Android e iOS no mesmo código Flutter.

## Quem usa e com que dados
- Usuários reais já usam o app em produção. **Regra de ouro:** só publicar com o "sim" explícito do dono (Daniel), depois de testar; a API precisa continuar **retrocompatível** (app antigo + servidor novo).
- Não há login. O "usuário" é um **perfil anônimo**: um código curto (ex.: `K7QM-4TXK`) + um segredo guardado no aparelho + apelido opcional.
- O servidor guarda só códigos, apelidos, datas e o necessário para o vínculo. **Nunca** áudio, e-mail, IP ou o que a pessoa toca. Detalhes em [05_SEGURANCA_E_PRIVACIDADE.md](05_SEGURANCA_E_PRIVACIDADE.md).

## Mapa da documentação
| Documento | Para quê |
|---|---|
| [01_ARQUITETURA.md](01_ARQUITETURA.md) | Camadas, diagramas e os fluxos principais |
| [02_APP_E_NUCLEO.md](02_APP_E_NUCLEO.md) | Como o app Flutter e o núcleo `afina_core` são organizados |
| [03_REGRAS_DE_NEGOCIO.md](03_REGRAS_DE_NEGOCIO.md) | Vínculo, papéis e visões, tarefas e status, aulas, horários livres, avisos, erros |
| [04_API_E_DADOS.md](04_API_E_DADOS.md) | Como a API funciona (contadores, limites, custo) e o modelo de dados |
| [05_SEGURANCA_E_PRIVACIDADE.md](05_SEGURANCA_E_PRIVACIDADE.md) | Guardrails, o que é coletado e o que nunca é |
| [06_TESTES.md](06_TESTES.md) | Como testar, o que está coberto, matriz de botões e regressão |
| [07_PAINEL_ADMIN.md](07_PAINEL_ADMIN.md) | O painel: abas, bugs, custos e como usar |
| [08_OPERACAO.md](08_OPERACAO.md) | Deploy, variáveis de ambiente, limites, rollback, incidentes |
| [09_DECISOES.md](09_DECISOES.md) | Por que as coisas são como são (decisões e alternativas) |
| [10_GUIA_DE_MANUTENCAO.md](10_GUIA_DE_MANUTENCAO.md) | Receitas passo a passo e armadilhas conhecidas |
| [11_HISTORICO.md](11_HISTORICO.md) | Etapas e pacotes já publicados |
| [12_DESIGN_SYSTEM.md](12_DESIGN_SYSTEM.md) | **Regra de interface**: medidas, componentes, ajustes em modal |
| [13_IDIOMAS.md](13_IDIOMAS.md) | **Português e inglês**: `tr()`, dicionário, como acrescentar um texto, o que acompanha o idioma |
| `referencia/` | **Gerado do código**: arquivos, API, dados, erros, ambiente (não edite à mão) |

Documentos de planejamento antigos (`ROADMAP_ETAPAS.md`, `PLANO_*.md`, `ARQUITETURA_PROFESSOR_ALUNO.md`, `CUSTOS_E_REGRESSAO.md`, `MATRIZ_BOTOES.md`) continuam na pasta como **histórico e roteiro**; a verdade atual está nos documentos numerados acima e em `referencia/`.

## Glossário
| Termo | Significado |
|---|---|
| **Perfil** | A identidade anônima: código + segredo + apelido. Não é cadastro. |
| **Código** | `XXXX-XXXX` (32 símbolos sem 0/O/1/I; 7 sorteados + 1 de verificação). Serve para ser encontrado e vinculado; **não dá acesso**. |
| **Segredo** | 256 bits aleatórios no aparelho; o servidor guarda só o hash. Prova que é o dono do perfil. |
| **Vínculo (online)** | Ligação professor ↔ aluno no servidor. Precisa estar ligado nos dois lados para aulas, tarefas e agenda chegarem. |
| **Modo professor** | Capacidade que qualquer perfil liga; não existe "conta de professor". |
| **Visão** (Aluno | Professor) | O que o *Meu espaço* mostra; quem tem os dois papéis alterna. |
| **Lado de aluno** (`hasTeacherSide`) | Tem professor, aula recebida ou agenda marcada por um professor. |
| **Aula** | Encerrada pelo professor e enviada ao aluno (com tarefas e observações). |
| **Aula marcada** (`ClassSlot`) | Um compromisso na agenda (única ou semanal). |
| **Horário livre** | Aula marcada "em aberto" que o professor publica; o aluno **pega** (primeiro que pegar leva). |
| **Fiz / validar / devolver** | Aluno sinaliza que fez uma tarefa; o professor valida (concluída) ou devolve (refazer). O professor é a fonte oficial do status. |
| **Contadores (`lr dr kr sr vr ar`)** | Números no perfil que mudam quando há novidade; o app consulta o barato `rev` e só baixa listas se algum mudou. |
| **Fingerprint** | Impressão digital de um bug (código + tela + 1ª linha); agrupa o mesmo erro. |
| **Pacote** | Um conjunto de mudanças publicado de uma vez, com testes e o "sim" do dono. |

## Primeiros passos
```bash
# Flutter 3.47.9 no PATH (no Windows do projeto: C:\Users\desktop\dev\flutter\bin)
flutter pub get
cd packages/afina_core && dart test        # núcleo (puro, rápido)
cd ../.. && flutter analyze                # análise estática
node --test api/*.test.js api/_lib/*.test.js   # API (sem rede, sem dependências)
flutter run -d web-server --web-port=8099  # abrir http://127.0.0.1:8099
node scripts/gen_docs.js                   # regenera docs/referencia/
```
Mais em [06_TESTES.md](06_TESTES.md) e [10_GUIA_DE_MANUTENCAO.md](10_GUIA_DE_MANUTENCAO.md).

## Regras do projeto (resumo)
1. **Publicar só com "sim" explícito**; testar antes (núcleo + API + `flutter analyze` + conferir a tela).
2. **API retrocompatível**: só acrescentar ações e campos; nunca mudar o significado dos existentes.
3. **Custo importa**: o plano gratuito do Upstash tem 500 mil comandos/mês. Todo recurso novo estima e mede os comandos do Redis; nada de polling pesado.
4. **Privacidade**: nada pessoal no servidor nem nos relatórios de erro.
5. **Limite da Vercel (Hobby): 12 funções.** Cada arquivo em `api/` conta (os testes ficam fora via `.vercelignore`).
