import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../feedback/feedback_service.dart';
import 'theme.dart';
import 'widgets.dart';

String _version() => kBuildId.isEmpty ? 'dev' : kBuildId.substring(0, kBuildId.length < 7 ? kBuildId.length : 7);
String _platform() => kIsWeb ? 'web' : defaultTargetPlatform.name;

const String _privacy =
    'Enviamos só a sua resposta e a versão do app, sem nome, e-mail nem áudio. '
    'Você escolhe se envia.';

void _afterSend(AppState app, bool delivered, String thanks) {
  app.say(delivered ? thanks : 'Sem conexão agora: guardei sua resposta e envio depois. Obrigado!');
}

/// Dar uma nota de 1 a 5 ao app (com comentário opcional).
Future<void> showRatingSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _RatingSheet(app: app),
  );
}

/// Pesquisa rápida: 2 perguntas.
Future<void> showSurveySheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _SurveySheet(app: app),
  );
}

class _RatingSheet extends StatefulWidget {
  final AppState app;
  const _RatingSheet({required this.app});

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late int _stars = widget.app.feedback.rating;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  static const _labels = ['', 'Ruim', 'Pode melhorar', 'Bom', 'Muito bom', 'Excelente'];

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok = await widget.app.feedback
        .sendRating(_stars, _comment.text, version: _version(), platform: _platform());
    if (!mounted) return;
    Navigator.pop(context);
    _afterSend(widget.app, ok, 'Obrigado pela sua nota!');
  }

  @override
  Widget build(BuildContext context) {
    final fb = widget.app.feedback;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Que nota você dá ao Notemusic?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(fb.rating > 0 ? 'Sua nota atual é ${fb.rating}. Você pode mudar.' : 'Toque nas estrelas.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 40,
                    tooltip: '$i estrela${i > 1 ? 's' : ''}',
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: i <= _stars ? const Color(0xFFFFC53D) : AppColors.textDim),
                  ),
              ],
            ),
            Center(
              child: SizedBox(
                height: 22,
                child: Text(_labels[_stars], style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Quer contar o motivo? (opcional)', alignLabelWithHint: true),
            ),
            Text(_privacy, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _stars == 0 || _busy ? null : _send,
              child: Text(_busy ? 'Enviando…' : 'Enviar nota'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurveySheet extends StatefulWidget {
  final AppState app;
  const _SurveySheet({required this.app});

  @override
  State<_SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<_SurveySheet> {
  String? _feature;
  final _improve = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _improve.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok = await widget.app.feedback
        .sendSurvey(_feature!, _improve.text, version: _version(), platform: _platform());
    if (!mounted) return;
    Navigator.pop(context);
    _afterSend(widget.app, ok, 'Obrigado! Sua opinião ajuda a melhorar o app.');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pesquisa rápida · 2 perguntas',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const Text('1. Qual recurso você mais usa?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final o in FeedbackService.featureOptions)
                  ChoiceChip(
                    label: Text(o),
                    selected: _feature == o,
                    onSelected: (_) => setState(() => _feature = o),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('2. O que poderia melhorar? (opcional)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _improve,
              maxLength: 200,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Escreva em poucas palavras'),
            ),
            Text(_privacy, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _feature == null || _busy ? null : _send,
              child: Text(_busy ? 'Enviando…' : 'Enviar respostas'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convite discreto para a pesquisa; só aparece quando está na hora e some depois
/// de respondido ou dispensado.
class FeedbackInviteCard extends StatelessWidget {
  final AppState app;
  const FeedbackInviteCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.feedback,
      builder: (context, _) {
        if (!app.feedback.surveyDue(sessions: app.sessionRecords.length)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.forum_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('Ajude a melhorar o app',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 4),
                Text('São 2 perguntas rápidas, de menos de 1 minuto. Anônimo.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => showSurveySheet(context, app),
                      child: const Text('Responder'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: app.feedback.snooze, child: const Text('Agora não')),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
