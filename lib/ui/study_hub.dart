import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../ai/coach_ai.dart';
import '../app_state.dart';
import 'design_system.dart';
import 'evolution_page.dart';
import 'gamify_ui.dart';
import 'markdown_lite.dart';
import 'scale_exercise_page.dart' show InsightTile;
import 'study_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// A primeira frase útil do plano (sem "##" nem "-"), para o cartão do Meu espaço.
String _firstLine(String md) {
  for (final raw in md.split('\n')) {
    if (raw.trimLeft().startsWith('#')) continue; // título do plano: não serve de frase
    final t = raw.replaceAll(RegExp(r'^[#\-\*\d\.\s]+'), '').replaceAll('**', '').trim();
    if (t.length >= 12) return t.length > 130 ? '${t.substring(0, 129)}…' : t;
  }
  return '';
}

/// O que o treinador diz no cartão do Meu espaço: o plano da semana, senão a primeira dica calculada no aparelho, senão um convite.
String coachHeadline(AppState app) {
  final plan = app.ai.planText;
  if (plan != null && plan.trim().isNotEmpty) {
    final l = _firstLine(plan);
    if (l.isNotEmpty) return l;
  }
  if (app.sessionRecords.isNotEmpty && app.insights.isNotEmpty) return app.insights.first.text;
  return tr('Faça um exercício guiado e o treinador começa a te orientar.');
}

/// O estudo do aluno num lugar só (Meu espaço): o treinador em destaque no topo e, embaixo, o resumo do estudo. Tocar abre a
/// página Estudo (Hoje, Evolução e Treinador).
class StudyHubCard extends StatelessWidget {
  final AppState app;
  const StudyHubCard({super.key, required this.app});

  void _open(BuildContext context, int tab) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudyHubPage(app: app, initialTab: tab)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.ai]),
      builder: (context, _) {
        final goal = app.dailyGoalMinutes;
        final todayMin = app.todaySeconds / 60;
        final streak = studyStreak(app.studySeconds, DateTime.now());
        final hasPlan = app.ai.planText != null;
        final today = DateTime.now();
        final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
        final mins = [for (final d in days) (app.studySeconds[AppState.dayKey(d)] ?? 0) / 60];
        final maxV = [goal, ...mins].reduce((a, b) => a > b ? a : b).clamp(5.0, 600.0);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // O treinador primeiro: é o que diz o que fazer.
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Ds.radiusCard),
            child: InkWell(
              borderRadius: BorderRadius.circular(Ds.radiusCard),
              onTap: () => _open(context, 2),
              child: Container(
                padding: const EdgeInsets.all(Ds.s16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Ds.radiusCard), border: Border.all(color: AppColors.info.withValues(alpha: 0.7))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.auto_awesome, size: 20, color: AppColors.info),
                    const SizedBox(width: Ds.s8),
                    Expanded(child: Text(tr('Seu treinador'), style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w800, fontSize: Ds.fontBody))),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                  ]),
                  const SizedBox(height: Ds.s8),
                  if (app.ai.busy)
                    Row(children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: Ds.s12),
                      Expanded(child: Text(app.ai.phase == AiPhase.queued ? tr('Você está na fila: o treinador responde assim que chegar a sua vez.') : tr('O treinador está preparando a resposta…'), style: const TextStyle(fontSize: 15, height: 1.35))),
                    ])
                  else
                    Text(coachHeadline(app), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.35)),
                  const SizedBox(height: Ds.s12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _open(context, 2),
                      icon: Icon(hasPlan ? Icons.checklist_rounded : Icons.auto_awesome, size: 18),
                      label: Text(hasPlan ? tr('Ver o plano da semana') : tr('Abrir o treinador')),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: Ds.s12),
          AppCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(Ds.radiusCard),
              onTap: () => _open(context, 0),
              child: Padding(
                padding: const EdgeInsets.all(Ds.s16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const DsIconBadge(Icons.auto_stories_rounded, size: 34),
                    const SizedBox(width: Ds.s12),
                    Expanded(child: Text(tr('Seu estudo'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                  ]),
                  const SizedBox(height: Ds.s12),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${todayMin.floor()} min', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
                        Text(todayMin >= goal ? tr('Meta de hoje feita!') : tr('hoje · meta {0} min', [goal.round()]), style: Ds.support()),
                      ]),
                    ),
                    SizedBox(
                      width: 120,
                      height: 40,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: (mins[i] / maxV * 40).clamp(3.0, 40.0),
                              decoration: BoxDecoration(color: mins[i] >= goal ? AppColors.inTune : AppColors.textDim.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: Ds.s12),
                  Row(children: [
                    Expanded(child: Text(streak.days == 1 ? tr('1 dia seguido') : tr('{0} dias seguidos', [streak.days]), style: Ds.support())),
                    TextButton.icon(
                      onPressed: () => _open(context, 1),
                      icon: const Icon(Icons.insights_rounded, size: 18),
                      label: Text(tr('Ver evolução')),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// A página Estudo: Hoje (cronômetro, Pomodoro e meta), Evolução (gráficos) e Treinador (plano e perguntas).
class StudyHubPage extends StatelessWidget {
  final AppState app;
  final int initialTab;
  const StudyHubPage({super.key, required this.app, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Estudo')),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.timer_outlined, size: 20), text: tr('Hoje'), height: 56),
              Tab(icon: const Icon(Icons.insights_rounded, size: 20), text: tr('Evolução'), height: 56),
              Tab(icon: const Icon(Icons.auto_awesome, size: 20), text: tr('Treinador'), height: 56),
            ],
          ),
        ),
        body: DsPageSafe(
          child: TabBarView(children: [
            ListenableBuilder(
              listenable: app,
              builder: (context, _) => ListView(padding: Ds.screen, children: [StudyCard(app: app), const DsGap(Ds.gap), GamifyCard(app: app)]),
            ),
            EvolutionBody(app: app),
            CoachTab(app: app),
          ]),
        ),
      ),
    );
  }
}

/// A aba Treinador: o plano da semana (IA, guardado), perguntas prontas, o histórico do que ele respondeu e as dicas do dia (calculadas no aparelho, de graça).
class CoachTab extends StatefulWidget {
  final AppState app;
  const CoachTab({super.key, required this.app});

  @override
  State<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends State<CoachTab> {
  AppState get app => widget.app;

  /// O texto da resposta que a pessoa já abriu (para o aviso "Resposta pronta" sumir depois de ler).
  String? _openedText;

  @override
  void initState() {
    super.initState();
    app.coachViewers++;
  }

  @override
  void dispose() {
    app.coachViewers--;
    super.dispose();
  }

  static List<String> get _questions => [
        tr('Por que erro a mesma nota?'),
        tr('Como estudo bem em 15 minutos?'),
        tr('O que ensaiar antes da próxima aula?'),
      ];

  Future<bool> _ensureConsent(BuildContext context) async {
    final ai = app.ai;
    if (ai.consent) return true;
    final ok = await showDsConfirm(
      context,
      title: tr('Usar o treinador com IA?'),
      body: tr('Para montar o plano, o app envia um resumo só com números e textos curtos: desvios de afinação, escalas, tempo de estudo e tarefas em aberto. Nunca vão áudio, nome ou código.'),
      confirmLabel: tr('Autorizar'),
      icon: Icons.auto_awesome,
    );
    if (ok) await ai.setConsent(true);
    return ok;
  }

  Future<void> _plan(BuildContext context) async {
    if (!await _ensureConsent(context)) return;
    final ctx = app.studyContextText();
    final req = buildPlanRequest(app.aiSummary(), ctx);
    await app.ai.askPlan(req, studyContextFingerprint(ctx));
  }

  Future<void> _ask(BuildContext context, String q) async {
    if (!await _ensureConsent(context)) return;
    final ctx = app.studyContextText();
    await app.ai.askQuestion(buildQuestionRequest(q, ctx, scalesPrompt: app.aiSummary()), q);
  }

  void _read(CoachEntry e, {bool canDelete = false}) {
    setState(() => _openedText = e.text);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CoachReaderPage(app: app, entry: e, canDelete: canDelete)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.ai]),
      builder: (context, _) {
        final ai = app.ai;
        final ctx = app.studyContextText();
        final can = canAskNewPlan(planAt: ai.planAt, planFingerprint: ai.planFingerprint, currentFingerprint: studyContextFingerprint(ctx), now: DateTime.now());
        final busy = ai.busy;
        final left = (CoachAi.dailyLimit - ai.usedCount).clamp(0, CoachAi.dailyLimit);
        final plan = ai.planText == null ? null : CoachEntry(kind: 'plan', title: 'plan', text: ai.planText!, at: ai.planAt ?? DateTime.now());
        final ready = !busy && ai.answerText != null && ai.history.isNotEmpty && ai.history.first.text == ai.answerText && _openedText != ai.answerText;
        return ListView(padding: Ds.screen, children: [
          _UsageRow(used: CoachAi.dailyLimit - left, limit: CoachAi.dailyLimit),
          const DsGap(Ds.s12),
          if (busy) ...[
            AppCard(child: _AiProgress(ai: ai)),
            const DsGap(Ds.gap),
          ],
          if (ai.phase == AiPhase.failed && ai.message != null && !busy) ...[
            AppCard(child: Text(ai.message!, style: TextStyle(color: AppColors.attention, fontSize: 14))),
            const DsGap(Ds.gap),
          ],
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.checklist_rounded, tr('Plano da semana'),
                  subtitle: plan == null ? tr('Um roteiro curto, feito pela IA com o que você estudou.') : tr('Gerado em {0}', [fmtDayMonth(plan.at)])),
              if (plan != null) ...[
                const SizedBox(height: Ds.s12),
                _Preview(text: plan.text, onTap: () => _read(plan)),
              ],
              const SizedBox(height: Ds.s12),
              Wrap(spacing: Ds.s8, runSpacing: Ds.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (plan == null)
                  FilledButton.icon(
                    onPressed: !busy && left > 0 ? () => _plan(context) : null,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(tr('Gerar plano')),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: () => _read(plan),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: Text(tr('Ler plano')),
                  ),
                  OutlinedButton.icon(
                    onPressed: !busy && can && left > 0 ? () => _plan(context) : null,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(tr('Atualizar')),
                  ),
                ],
              ]),
              if (left == 0)
                Padding(padding: const EdgeInsets.only(top: Ds.s8), child: Text(tr('Você usou os {0} pedidos de hoje. Volte amanhã.', [CoachAi.dailyLimit]), style: TextStyle(color: AppColors.attention, fontSize: 13)))
              else if (plan != null && !can)
                Padding(padding: const EdgeInsets.only(top: Ds.s8), child: Text(tr('O plano está em dia.'), style: Ds.support())),
            ]),
          ),
          const DsGap(Ds.gap),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.forum_outlined, tr('Pergunte ao treinador'), subtitle: tr('Toque numa pergunta e a resposta fica no histórico.')),
              const SizedBox(height: Ds.s12),
              if (ready) ...[
                _ReadyTile(question: ai.answerQuestion ?? '', onTap: () => _read(ai.history.first, canDelete: true)),
                const SizedBox(height: Ds.s8),
              ],
              for (final q in _questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: Ds.s8),
                  child: Material(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: busy || left == 0 ? null : () => _ask(context, q),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: Ds.tap),
                        padding: const EdgeInsets.symmetric(horizontal: Ds.s12, vertical: Ds.s8),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outline)),
                        child: Row(children: [
                          Expanded(child: Text(q, style: const TextStyle(fontSize: 14.5))),
                          Icon(Icons.north_east_rounded, size: 18, color: AppColors.textDim),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const DsGap(Ds.gap),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.history_rounded, tr('Histórico'), subtitle: ai.history.isEmpty ? tr('O que o treinador responder fica guardado aqui.') : null),
              if (ai.history.isNotEmpty) ...[
                const SizedBox(height: Ds.s8),
                for (final e in ai.history.take(4)) _EntryTile(entry: e, onTap: () => _read(e, canDelete: true)),
                if (ai.history.length > 4)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CoachHistoryPage(app: app))),
                      child: Text(tr('Ver todos ({0})', [ai.history.length])),
                    ),
                  ),
              ],
            ]),
          ),
          const DsGap(Ds.gap),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.lightbulb_outline_rounded, tr('Dicas de hoje'), subtitle: tr('Calculadas no aparelho, sem gastar IA.')),
              const SizedBox(height: Ds.s8),
              if (app.sessionRecords.isEmpty)
                Text(tr('Faça um exercício guiado para receber orientações.'), style: Ds.support())
              else
                for (final i in app.insights) InsightTile(insight: i),
            ]),
          ),
          if (app.myLessons.any((l) => l.notes.isNotEmpty)) ...[
            const DsGap(Ds.gap),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: Icon(Icons.chat_bubble_outline_rounded, color: AppColors.textDim),
                title: Text(tr('Usar as observações do professor'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('O treinador lê o que o professor anotou (sem nomes) para orientar melhor. Desligado por padrão.'), style: Ds.support()),
                value: app.aiTeacherContext,
                onChanged: app.setAiTeacherContext,
              ),
            ),
          ],
        ]);
      },
    );
  }
}

/// O texto sem marcações do Markdown, em poucas linhas, para dar uma ideia do conteúdo.
String _plain(String md) => md.replaceAll(RegExp(r'(^|\n)\s*[-•]\s+'), ' ').replaceAll(RegExp(r'[#*_`>]'), '').replaceAll(RegExp(r'\s*\n+\s*'), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

String _entryTitle(CoachEntry e) => e.isPlan ? tr('Plano da semana') : e.title;

class _Preview extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Preview({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Ds.s12),
            child: Text(_plain(text), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, height: 1.4)),
          ),
        ),
      );
}

/// Aviso de que a resposta chegou: um toque abre a leitura.
class _ReadyTile extends StatelessWidget {
  final String question;
  final VoidCallback onTap;
  const _ReadyTile({required this.question, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: Ds.tap),
            padding: const EdgeInsets.symmetric(horizontal: Ds.s12, vertical: Ds.s8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.info.withValues(alpha: 0.5))),
            child: Row(children: [
              Icon(Icons.mark_chat_read_outlined, size: 20, color: AppColors.info),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Resposta pronta'), style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(question, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5)),
                ]),
              ),
              Text(tr('Ler'), style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Uma linha do histórico: o que foi pedido, quando e o começo da resposta.
class _EntryTile extends StatelessWidget {
  final CoachEntry entry;
  final VoidCallback onTap;
  const _EntryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Ds.tap),
          padding: const EdgeInsets.symmetric(vertical: Ds.s8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(entry.isPlan ? Icons.checklist_rounded : Icons.forum_outlined, size: 20, color: AppColors.textDim),
            ),
            const SizedBox(width: Ds.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_entryTitle(entry), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                Text('${fmtDayMonth(entry.at)} · ${_plain(entry.text)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Ds.support()),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ]),
        ),
      );
}

/// Leitura de uma resposta do treinador, com texto confortável, copiar e (no histórico) apagar.
class CoachReaderPage extends StatelessWidget {
  final AppState app;
  final CoachEntry entry;
  final bool canDelete;
  const CoachReaderPage({super.key, required this.app, required this.entry, this.canDelete = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(entry.isPlan ? tr('Plano da semana') : tr('Resposta do treinador'))),
      body: DsPageSafe(
        child: ListView(padding: Ds.screen, children: [
          if (!entry.isPlan) ...[
            Text(entry.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.25)),
            const SizedBox(height: Ds.s4),
          ],
          Text(tr('Gerado em {0}', [fmtDayMonth(entry.at)]), style: Ds.support()),
          const SizedBox(height: Ds.s12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Ds.s16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.outline)),
            child: MarkdownLite(entry.text),
          ),
          const SizedBox(height: Ds.s12),
          Text(tr('Feito por IA: pode errar. Use junto com o seu professor.'), style: Ds.support()),
          const SizedBox(height: Ds.s12),
          Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            CopyAnswerButton(entry.text),
            if (canDelete)
              TextButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final ok = await showDsConfirm(context, title: tr('Apagar do histórico?'), body: tr('Esta resposta some deste aparelho.'), confirmLabel: tr('Apagar'), icon: Icons.delete_outline_rounded);
                  if (!ok) return;
                  await app.ai.deleteEntry(entry);
                  nav.pop();
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(tr('Apagar')),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Todas as respostas guardadas.
class CoachHistoryPage extends StatelessWidget {
  final AppState app;
  const CoachHistoryPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Histórico'))),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app.ai,
          builder: (context, _) => ListView(padding: Ds.screen, children: [
            if (app.ai.history.isEmpty) Text(tr('O que o treinador responder fica guardado aqui.'), style: Ds.support()),
            for (final e in app.ai.history)
              _EntryTile(
                entry: e,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CoachReaderPage(app: app, entry: e, canDelete: true))),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Andamento do pedido: enviando ou na fila (com contagem), e o botão de cancelar.
class _AiProgress extends StatelessWidget {
  final CoachAi ai;
  const _AiProgress({required this.ai});

  @override
  Widget build(BuildContext context) {
    if (ai.phase == AiPhase.queued) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ai.queuePosition != null
            ? tr('Muita gente usando agora. Você é o {0}º da fila: sua vez em {1}s.', [ai.queuePosition, ai.queuedSeconds])
            : tr('Muita gente usando agora. Você está na fila: nova tentativa em {0}s (tentativa {1}/{2}).', [ai.queuedSeconds, ai.attempt, CoachAi.maxAttempts])),
        const SizedBox(height: Ds.s8),
        Text(tr('Pode sair desta tela e usar o app: avisamos quando ficar pronto. Se fechar o app, peça de novo.'), style: Ds.support()),
        const SizedBox(height: Ds.s8),
        OutlinedButton(onPressed: ai.cancel, child: Text(tr('Cancelar'))),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Ds.s12),
        Expanded(child: Text(tr('O treinador está pensando…'))),
      ]),
      const SizedBox(height: Ds.s8),
      Text(tr('Pode levar até 1 minuto. Pode sair desta tela e usar o app: avisamos quando ficar pronto.'), style: Ds.support()),
    ]);
  }
}

/// O limite do dia, sempre à vista: bolinhas cheias = pedidos usados; a conta renova amanhã.
class _UsageRow extends StatelessWidget {
  final int used;
  final int limit;
  const _UsageRow({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final left = limit - used;
    return Row(children: [
      Icon(Icons.speed_rounded, size: 18, color: AppColors.textDim),
      const SizedBox(width: Ds.s8),
      Expanded(
        child: Text(
          left == 0 ? tr('Pedidos de hoje: acabaram. Voltam amanhã.') : tr('Pedidos ao treinador hoje: {0} de {1} usados', [used, limit]),
          style: TextStyle(color: left == 0 ? AppColors.attention : AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      for (var i = 0; i < limit; i++)
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(shape: BoxShape.circle, color: i < used ? (left == 0 ? AppColors.attention : AppColors.info) : AppColors.outline),
        ),
    ]);
  }
}
