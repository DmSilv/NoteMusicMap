import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../ai/coach_ai.dart';
import '../app_state.dart';
import 'design_system.dart';
import 'evolution_page.dart';
import 'markdown_lite.dart';
import 'scale_exercise_page.dart' show InsightTile, copyAiSummary;
import 'study_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// A primeira frase útil do plano (sem "##" nem "-"), para o cartão do Meu espaço.
String _firstLine(String md) {
  for (final raw in md.split('\n')) {
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
              builder: (context, _) => ListView(padding: Ds.screen, children: [StudyCard(app: app)]),
            ),
            EvolutionBody(app: app),
            CoachTab(app: app),
          ]),
        ),
      ),
    );
  }
}

/// A aba Treinador: o plano da semana (IA, guardado), as dicas do dia (calculadas no aparelho, de graça) e perguntas prontas.
class CoachTab extends StatelessWidget {
  final AppState app;
  const CoachTab({super.key, required this.app});

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.ai]),
      builder: (context, _) {
        final ai = app.ai;
        final ctx = app.studyContextText();
        final can = canAskNewPlan(planAt: ai.planAt, planFingerprint: ai.planFingerprint, currentFingerprint: studyContextFingerprint(ctx), now: DateTime.now());
        final busy = ai.busy;
        return ListView(padding: Ds.screen, children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.checklist_rounded, tr('Plano da semana')),
              const SizedBox(height: Ds.s8),
              if (ai.planText == null)
                Text(tr('O treinador monta um plano com o que você tocou, o tempo que estudou e as tarefas do seu professor. Pede uma vez por semana e fica guardado.'), style: Ds.support())
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Ds.s12),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                  child: MarkdownLite(ai.planText!),
                ),
                const SizedBox(height: Ds.s4),
                Text(tr('Gerado em {0}. Gerado por IA: pode errar; use como sugestão, junto com o seu professor.', [fmtDayMonth(ai.planAt ?? DateTime.now())]), style: Ds.support()),
              ],
              const SizedBox(height: Ds.s12),
              if (busy) _AiProgress(ai: ai) else ...[
                Wrap(spacing: Ds.s8, runSpacing: Ds.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  FilledButton.icon(
                    onPressed: can ? () => _plan(context) : null,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(ai.planText == null ? tr('Gerar meu plano') : tr('Atualizar o plano')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => copyAiSummary(app),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(tr('Copiar resumo')),
                  ),
                  if (ai.planText != null && !can) Text(tr('O plano está em dia.'), style: Ds.support()),
                ]),
              ],
              if (ai.phase == AiPhase.failed && ai.message != null)
                Padding(padding: const EdgeInsets.only(top: Ds.s8), child: Text(ai.message!, style: TextStyle(color: AppColors.attention, fontSize: 13))),
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
          const DsGap(Ds.gap),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.forum_outlined, tr('Pergunte ao treinador')),
              const SizedBox(height: Ds.s8),
              for (final q in _questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: Ds.s8),
                  child: Material(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: busy ? null : () => _ask(context, q),
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
              if (ai.answerText != null && !busy) ...[
                const SizedBox(height: Ds.s12),
                Text(ai.answerQuestion ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: Ds.s8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Ds.s12),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                  child: MarkdownLite(ai.answerText!),
                ),
                Align(alignment: Alignment.centerRight, child: CopyAnswerButton(ai.answerText!)),
              ],
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
        OutlinedButton(onPressed: ai.cancel, child: Text(tr('Cancelar'))),
      ]);
    }
    return Row(children: [
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: Ds.s12),
      Expanded(child: Text(tr('O treinador está pensando…'))),
    ]);
  }
}
