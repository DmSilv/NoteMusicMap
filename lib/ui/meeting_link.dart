import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'safe_input.dart';
import 'theme.dart';

/// Abre o link da aula online no navegador do aparelho. Sites conhecidos (Meet, Zoom, Teams…) abrem direto;
/// qualquer outro mostra antes o endereço, para a pessoa saber para onde está indo.
Future<void> openMeetingLink(BuildContext context, AppState app, String link) async {
  final url = meetingUrl(link);
  if (url == null) {
    app.say('O link desta aula não é válido.');
    return;
  }
  if (!isKnownMeetingLink(url)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abrir este link?'),
        content: Text('Você vai abrir ${meetingHost(url)}.\nSó continue se você confia em quem enviou.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Abrir')),
        ],
      ),
    );
    if (ok != true) return;
  }
  try {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened) app.say('Não foi possível abrir o link.');
  } catch (_) {
    app.say('Não foi possível abrir o link.');
  }
}

/// "Presencial | Online" mais o campo do link da sala (pode ficar vazio e ser posto depois).
/// Avisa o formulário de cada mudança em [onChanged] (modo e link já sem espaços nas pontas).
class MeetingEditor extends StatefulWidget {
  final AppState app;
  final String mode;
  final String link;
  final void Function(String mode, String link) onChanged;

  /// Dentro de um cartão: sem o espaço extra em cima.
  final bool compact;
  const MeetingEditor({super.key, required this.app, required this.mode, required this.link, required this.onChanged, this.compact = false});

  @override
  State<MeetingEditor> createState() => _MeetingEditorState();
}

class _MeetingEditorState extends State<MeetingEditor> {
  AppState get app => widget.app;
  late String mode = widget.mode == kModeOnline ? kModeOnline : kModeInPerson;
  late final TextEditingController c = TextEditingController(text: widget.link);

  @override
  void initState() {
    super.initState();
    if (mode == kModeOnline && c.text.isEmpty && app.meetDefault.isNotEmpty) c.text = app.meetDefault;
    // Avisa o formulário do valor inicial (modo escolhido e link padrão já preenchido).
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(mode, mode == kModeOnline ? c.text.trim() : '');

  String? get _err => mode == kModeOnline && c.text.trim().isNotEmpty && meetingUrl(c.text) == null
      ? 'Link inválido. Use um endereço https, como o do Meet ou do Zoom.'
      : null;

  Future<void> _create() async {
    try {
      await launchUrl(Uri.parse('https://meet.new'), mode: LaunchMode.externalApplication);
    } catch (_) {
      app.say('Não foi possível abrir o Meet.');
    }
  }

  Future<void> _saveDefault() async {
    final e = await app.setMeetDefault(c.text);
    app.say(e ?? 'Link padrão guardado: as próximas aulas online já saem com ele.');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final valid = meetingUrl(c.text) != null;
    final isDefault = valid && meetingUrl(c.text) == app.meetDefault;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.only(top: widget.compact ? 0 : 16, bottom: Ds.s8),
        child: Text('Onde será a aula', style: Ds.section()),
      ),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: kModeInPerson, icon: Icon(Icons.place_outlined, size: 18), label: Text('Presencial')),
          ButtonSegment(value: kModeOnline, icon: Icon(Icons.videocam_outlined, size: 18), label: Text('Online')),
        ],
        selected: {mode},
        onSelectionChanged: (s) => setState(() {
          mode = s.first;
          if (mode == kModeOnline && c.text.isEmpty && app.meetDefault.isNotEmpty) c.text = app.meetDefault;
          _emit();
        }),
      ),
      if (mode == kModeOnline) ...[
        const SizedBox(height: Ds.s12),
        TextField(
          controller: c,
          keyboardType: TextInputType.url,
          autocorrect: false,
          inputFormatters: const [SafeText(kMaxMeetLink)],
          decoration: InputDecoration(
            labelText: 'Link da sala (pode deixar para depois)',
            hintText: 'https://meet.google.com/…',
            errorText: _err,
            prefixIcon: const Icon(Icons.link, size: 20),
          ),
          onChanged: (_) => setState(_emit),
        ),
        Wrap(spacing: Ds.s8, children: [
          TextButton.icon(onPressed: _create, icon: const Icon(Icons.add_link, size: 18), label: const Text('Criar sala no Meet')),
          if (valid && !isDefault)
            TextButton.icon(onPressed: _saveDefault, icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: const Text('Guardar como link padrão')),
        ]),
        if (!valid && c.text.trim().isEmpty)
          Text('Sem link por enquanto: a aula fica marcada como online e você coloca o link depois.', style: Ds.support()),
        if (isDefault) Text('Este é o seu link padrão.', style: Ds.support()),
      ],
    ]);
  }
}

/// Janela rápida para pôr, trocar ou tirar o link de uma aula online já marcada.
/// Devolve o link novo, '' para tirar, ou null se cancelou.
Future<String?> showMeetLinkSheet(BuildContext context, AppState app, {String initial = ''}) {
  final c = TextEditingController(text: initial.isEmpty ? app.meetDefault : initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, MediaQuery.of(ctx).viewInsets.bottom + Ds.s24),
      child: StatefulBuilder(
        builder: (ctx, setS) {
          final bad = c.text.trim().isNotEmpty && meetingUrl(c.text) == null;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Link da aula online', style: Ds.title()),
            const SizedBox(height: Ds.s12),
            TextField(
              controller: c,
              keyboardType: TextInputType.url,
              autocorrect: false,
              autofocus: true,
              inputFormatters: const [SafeText(kMaxMeetLink)],
              decoration: InputDecoration(
                hintText: 'https://meet.google.com/…',
                errorText: bad ? 'Link inválido. Use um endereço https.' : null,
                prefixIcon: const Icon(Icons.link, size: 20),
              ),
              onChanged: (_) => setS(() {}),
            ),
            const SizedBox(height: Ds.s16),
            Row(children: [
              if (initial.isNotEmpty)
                TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Tirar link')),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              const SizedBox(width: Ds.s8),
              FilledButton(
                onPressed: bad || c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, meetingUrl(c.text)),
                child: const Text('Salvar'),
              ),
            ]),
          ]);
        },
      ),
    ),
  );
}
