import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'agenda_page.dart';
import 'hub_section.dart' show shareTeacherInvite;
import 'safe_input.dart';
import '../ai/coach_ai.dart';
import 'dictation_button.dart';
import 'dart:async';
import 'markdown_lite.dart';
import 'methods_page.dart';
import 'qr_scan_page.dart';
import 'scale_exercise_page.dart';
import 'student_identity.dart';
import 'task_form_page.dart';
import 'validation_ui.dart';
import 'theme.dart';
import 'widgets.dart';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

Future<String?> _askText(BuildContext context, String title, String label,
    {String initial = '', bool multiline = false, String action = 'Salvar', AppState? voice}) async {
  final ctl = TextEditingController(text: initial);
  final v = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        inputFormatters: [SafeText(multiline ? kMaxNote : kMaxTitle, multiline: multiline)],
        autofocus: true,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          // Microfone para ditar (só onde o texto é livre).
          suffixIcon: voice == null ? null : DictationButton(app: voice, controller: ctl),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(action)),
      ],
    ),
  );
  ctl.dispose();
  return v;
}

/// "Novo aluno": nome (obrigatório) e código do aluno (opcional, o que ele vê em
/// Configurações › Meu perfil). Devolve (nome, código) ou null se cancelar.
Future<(String, String?)?> _newStudentDialog(BuildContext context, AppState app, {String? code0}) async {
  final name = TextEditingController();
  final code = TextEditingController(text: code0 ?? '');
  String? nameErr, codeErr;
  final r = await showDialog<(String, String?)>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('Novo aluno'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                inputFormatters: const [SafeText.name()],
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nome do aluno',
                  errorText: nameErr,
                  suffixIcon: DictationButton(app: app, controller: name),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                inputFormatters: codeFormatters,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Código do aluno',
                  hintText: 'K7QM-4TXD',
                  helperText: 'Toque na câmera para ler o QR do aluno, ou digite o código (ele vê no perfil).',
                  helperMaxLines: 3,
                  errorText: codeErr,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: 'Ler QR do aluno',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final s = await scanShareCode(c,
                          title: 'Ler QR do aluno',
                          want: 'aluno',
                          check: (code) => app.checkStudent('aluno', code).code,
                          onCamera: app.setCameraStatus);
                      if (s == null) return;
                      setS(() {
                        code.text = s.code;
                        codeErr = null;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              // Regras: nada de aluno com o seu próprio código/nome, nem repetido.
              final r = app.checkStudent(n, code.text);
              if (!r.ok) {
                setS(() {
                  nameErr = r.name;
                  codeErr = r.code;
                });
                return;
              }
              Navigator.pop(c, (n, code.text.trim().isEmpty ? null : code.text));
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  code.dispose();
  return r;
}

/// Chamado ao abrir o app por um link/QR de aluno (`?aluno=K7QM-4TXD`): leva o
/// professor direto ao cadastro, com o código já preenchido.
Future<void> handleIncomingStudentCode(BuildContext context, AppState app) async {
  final code = app.incomingStudentCode;
  if (code == null) return;
  app.incomingStudentCode = null;
  final known = app.studentByCode(code);
  if (known != null) {
    app.say('${known.name} já está na sua lista.');
    return;
  }
  final problem = app.checkStudent('aluno', code).code; // próprio código, professor etc.
  if (problem != null) {
    app.say(problem);
    return;
  }
  if (!app.teacherMode) {
    final on = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Código de aluno recebido'),
        content: Text('O código $code foi lido. Para cadastrar e acompanhar este aluno, ligue o modo professor '
            '(você continua usando o app normalmente como aluno).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ligar e adicionar')),
        ],
      ),
    );
    if (on != true || !context.mounted) return;
    app.setTeacherMode(true);
  }
  final r = await _newStudentDialog(context, app, code0: code);
  if (r != null) {
    app.addStudent(r.$1, code: r.$2);
    app.say('${r.$1} foi adicionado à sua lista.');
  }
}

/// Guia curto e didático do que a área do professor faz, aberto no primeiro acesso.
class _HowItWorks extends StatelessWidget {
  final bool open;
  const _HowItWorks({required this.open});

  static const _steps = <(IconData, String, String)>[
    (
      Icons.person_add_alt_1,
      '1. Cadastre o aluno',
      'Mais rápido: peça ao aluno para abrir o perfil dele (ícone no topo do app) e aponte a câmera '
          'do seu celular para o QR. O Notemusic abre já com o código e você só confirma o nome. '
          'Também dá para digitar o código (algo como K7QM-4TXD) em "Novo aluno", ou cadastrar só pelo nome '
          'e colocar o código depois, no menu do aluno. Não precisa de e-mail nem de cadastro completo.'
    ),
    (
      Icons.play_circle_outline,
      '2. Comece a aula',
      'Abra o aluno e toque em "Começar a aula". Enquanto ela durar, cada exercício feito no app entra no '
          'histórico desse aluno, e não no seu. Dá para pausar e, ao encerrar, o que você passou vai para o aluno.'
    ),
    (
      Icons.assignment_outlined,
      '3. Passe tarefas',
      'Abra o aluno e toque em "Nova tarefa". Escolha o tipo: escala ou arpejo (com meta de acerto, '
          'concluída sozinha), método e lição (ex.: Suzuki · Lição 5), repertório ou outra atividade. '
          'Em todas há um campo de observações para o que merece atenção; use o microfone do teclado para ditar. '
          'Toque numa tarefa para editar.'
    ),
    (
      Icons.insights,
      '4. Acompanhe a evolução',
      'Na página do aluno você vê a média, o melhor resultado, a tendência e orientações automáticas '
          'sobre as notas que ele mais desafina. Use "Anotar" para registrar suas observações.'
    ),
    (
      Icons.ios_share,
      '5. Compartilhe',
      'No menu ⋮ do aluno: "Copiar relatório" (para enviar por mensagem ou e-mail), "Relatório com IA" '
          'e "Copiar dados" para levar o aluno a outro aparelho (use "Importar dados de um aluno" lá).'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(open), // reabre quando a lista fica vazia
          initiallyExpanded: open,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          leading: Icon(Icons.help_outline, color: AppColors.accent),
          title: const Text('Como funciona', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Cadastrar, acompanhar e compartilhar, passo a passo',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (icon, title, text) in _steps)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: AppColors.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(text, style: const TextStyle(fontSize: 13, height: 1.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Vínculo online: quando você lê o QR do aluno (ou ele lê o seu), o vínculo aparece nos dois '
                'aparelhos em poucos segundos. O aluno que ler o seu QR entra sozinho na sua lista, e você '
                'entra na lista de professores dele. Qualquer um pode encerrar o vínculo quando quiser. '
                'Funciona com o "Vínculo online" ligado (no perfil de cada um).\n\n'
                'Aulas: na ficha do aluno, toque em "Começar a aula". Passe as tarefas e observações normalmente e, '
                'ao tocar em "Encerrar", tudo o que você passou naquela aula vai para o aluno, em Meu perfil › Minhas aulas. '
                'Dá para pausar. O histórico de exercícios do aluno continua só no aparelho dele e no seu.',
                style: TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Área do professor: alunos, tarefas, observações e relatórios (tudo neste aparelho).
class TeacherPage extends StatefulWidget {
  final AppState app;
  const TeacherPage({super.key, required this.app});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.watchLinks(); // alunos que se vinculam pelo QR aparecem sozinhos
    app.markTab('teacher');
  }

  /// Modo "Gerenciar": caixas de seleção para excluir vários alunos.
  bool _manage = false;
  final Set<String> _selected = {};
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    app.unwatchLinks();
    _search.dispose();
    super.dispose();
  }

  bool _matches(Student s) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) || (s.code ?? '').toLowerCase().contains(q.replaceAll('-', ''));
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    if (n == 0) return;
    final ok = await _confirmDelete(
        context,
        n == 1 ? 'Excluir 1 aluno?' : 'Excluir $n alunos?',
        'Apaga o histórico, as tarefas e as observações ${n == 1 ? 'deste aluno' : 'destes alunos'} '
            'neste aparelho${_selected.any(app.hasLessonWith) ? ', e descarta a aula em andamento' : ''}. Não dá para desfazer.');
    if (!ok) return;
    final removed = app.removeStudents(Set.of(_selected));
    setState(() {
      _selected.clear();
      _manage = false;
    });
    app.say(removed == 1 ? 'Aluno excluído.' : '$removed alunos excluídos.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alunos'),
        actions: [
          HelpButton(
            title: 'Como funciona',
            sections: [for (final (_, t, x) in _HowItWorks._steps) (t, x)],
          ),
          IconButton(
            tooltip: 'Agenda do professor',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AgendaPage(app: app))),
          ),
          ListenableBuilder(
            listenable: app,
            builder: (context, _) => app.students.isEmpty || app.teacherLocked
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: () => setState(() {
                      _manage = !_manage;
                      _selected.clear();
                    }),
                    icon: Icon(_manage ? Icons.check : Icons.checklist, size: 20),
                    label: Text(_manage ? 'Concluir' : 'Gerenciar'),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => app.teacherLocked ? _PinGate(app: app) : _home(context),
        ),
      ),
    );
  }

  Widget _home(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _LessonBanner(app: app),
        const SizedBox(height: 10),
        if (app.students.length > 5)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _search,
              inputFormatters: const [SafeText.name()],
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar aluno por nome ou código',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        })),
              ),
            ),
          ),
        if (_manage && app.students.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    final shown = app.students.where(_matches).map((s) => s.id).toSet();
                    if (_selected.containsAll(shown)) {
                      _selected.removeAll(shown);
                    } else {
                      _selected.addAll(shown);
                    }
                  }),
                  child: const Text('Selecionar todos'),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_selected.isEmpty ? 'Excluir' : 'Excluir (${_selected.length})'),
                ),
              ],
            ),
          ),
        for (final s in app.students.where(_matches)) _studentCard(context, s),
        if (app.students.isNotEmpty && !app.students.any(_matches))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('Nenhum aluno encontrado.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ),
        if (app.students.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('Nenhum aluno ainda. Toque em "Novo aluno" ou no "?" para ver como funciona.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ),
        const SizedBox(height: 4),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () async {
            final r = await _newStudentDialog(context, app);
            if (r != null) app.addStudent(r.$1, code: r.$2);
          },
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Novo aluno', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () async {
            final s = await scanShareCode(context,
                title: 'Ler QR do aluno', want: 'aluno', check: (code) => app.checkStudent('aluno', code).code,
                          onCamera: app.setCameraStatus);
            if (s == null || !context.mounted) return;
            final r = await _newStudentDialog(context, app, code0: s.code);
            if (r != null) app.addStudent(r.$1, code: r.$2);
          },
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Ler QR do aluno', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => MethodsPage(app: app))),
          icon: const Icon(Icons.library_books_outlined),
          label: Text(app.methodLibrary.isEmpty
              ? 'Meus métodos e lições'
              : 'Meus métodos e lições (${app.methodLibrary.length})'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final t = await _askText(context, 'Importar aluno',
                'Cole aqui os dados copiados do outro aparelho',
                multiline: true, action: 'Importar');
            if (t != null && t.trim().isNotEmpty) app.say(app.importStudentText(t));
          },
          icon: const Icon(Icons.download),
          label: const Text('Importar dados de um aluno'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final pin = await _askText(context, 'Trava com senha (opcional)',
                'Senha de 4 números (vazio remove)',
                action: 'Definir');
            if (pin != null) {
              final p = pin.trim();
              if (p.isEmpty) {
                app.setTeacherPin(null);
                app.say('Trava removida');
              } else if (RegExp(r'^\d{4}$').hasMatch(p)) {
                app.setTeacherPin(p);
                app.say('Trava definida: peça a senha ao abrir esta área');
              } else {
                app.say('Use exatamente 4 números');
              }
            }
          },
          icon: Icon(app.teacherPinHash == null ? Icons.lock_open : Icons.lock_outline),
          label: Text(app.teacherPinHash == null ? 'Definir senha desta área' : 'Trocar ou remover a senha'),
        ),
      ],
    );
  }

  Widget _studentCard(BuildContext context, Student s) {
    final sum = summarizeStudent(s);
    final open = s.tasks.where((t) => !t.done).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _manage
              ? () => setState(() => _selected.contains(s.id) ? _selected.remove(s.id) : _selected.add(s.id))
              : () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id))),
          child: Row(
            children: [
              if (_manage)
                Checkbox(
                  value: _selected.contains(s.id),
                  onChanged: (v) => setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                )
              else
                CircleAvatar(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (s.code != null)
                      Row(children: [
                        Text('Código ${s.code}',
                            style: TextStyle(color: AppColors.textDim, fontSize: 12, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        linkBadge(s),
                      ]),
                    if (remoteNameOf(s) != null)
                      Text('Nome no perfil dele: ${remoteNameOf(s)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      sum.sessions == 0
                          ? 'Sem exercícios ainda'
                          : '${sum.sessions} sessões · média ${(sum.recentAverage! * 100).round()}% · última ${_day(sum.last!)}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                    if (app.awaitingOf(s).isNotEmpty)
                      Text('${app.awaitingOf(s).length} para validar',
                          style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    if (open > 0)
                      Text('$open tarefa${open > 1 ? 's' : ''} em aberto',
                          style: TextStyle(color: AppColors.flat, fontSize: 12.5)),
                  ],
                ),
              ),
              if (!_manage)
                PopupMenuButton<String>(
                  tooltip: 'Opções de ${s.name}',
                  icon: Icon(Icons.more_vert, color: AppColors.textDim),
                  onSelected: (v) async {
                    switch (v) {
                      case 'open':
                        await Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id)));
                      case 'rename':
                        await _renameStudent(context, app, s);
                      case 'code':
                        await _editStudentCode(context, app, s);
                      case 'delete':
                        final ok = await _confirmDelete(context, 'Excluir ${s.name}?',
                            'Apaga o histórico, as tarefas e as observações deste aluno neste aparelho'
                                '${app.hasLessonWith(s.id) ? ', e descarta a aula em andamento com ele' : ''}. Não dá para desfazer.');
                        if (ok) {
                          app.removeStudent(s.id);
                          app.say('${s.name} foi excluído.');
                        }
                    }
                  },
                  itemBuilder: (c) => const [
                    PopupMenuItem(value: 'open', child: Text('Abrir')),
                    PopupMenuItem(value: 'rename', child: Text('Renomear')),
                    PopupMenuItem(value: 'code', child: Text('Código do aluno')),
                    PopupMenuItem(value: 'delete', child: Text('Excluir aluno')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String title, String text) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> _renameStudent(BuildContext context, AppState app, Student s) async {
  final n = await _askText(context, 'Renomear', 'Nome', initial: s.name, voice: app);
  if (n == null || n.trim().isEmpty) return;
  final err = app.checkStudent(n, s.code ?? '', exceptId: s.id).name;
  if (err != null) {
    app.say(err);
    return;
  }
  s.name = n.trim();
  app.setActiveStudent(app.activeStudentId); // salva e atualiza
}

Future<void> _editStudentCode(BuildContext context, AppState app, Student s) async {
  final c = await _askText(context, 'Código do aluno', 'Código (ex.: K7QM-4TXD)',
      initial: s.code ?? '', action: 'Salvar');
  if (c == null) return;
  final err = app.checkStudentCode(c, exceptId: s.id);
  if (err != null) {
    app.say(err);
  } else {
    app.setStudentCode(s.id, c);
  }
}

class _PinGate extends StatefulWidget {
  final AppState app;
  const _PinGate({required this.app});

  @override
  State<_PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<_PinGate> {
  final _ctl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _try() {
    if (!widget.app.unlockTeacher(_ctl.text.trim())) {
      setState(() => _error = 'Senha incorreta');
      _ctl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 44),
            const SizedBox(height: 10),
            const Text('Alunos protegidos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Digite a senha de 4 números.', style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 14),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _ctl,
                autofocus: true,
                obscureText: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(errorText: _error, counterText: ''),
                onSubmitted: (_) => _try(),
                onChanged: (v) {
                  if (v.length == 4) _try();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalhe de um aluno: evolução, orientações, tarefas e observações.
class StudentPage extends StatelessWidget {
  final AppState app;
  final String studentId;
  const StudentPage({super.key, required this.app, required this.studentId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.studentById(studentId);
        if (s == null) return const Scaffold(body: SizedBox.shrink());
        final sum = summarizeStudent(s);
        final tips = analyzePractice(s.sessions, flats: app.flatsForText).take(4).toList();
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Alunos', style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w600)),
              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'report':
                      await Clipboard.setData(ClipboardData(text: studentReport(s, flats: app.flatsForText)));
                      app.say('Relatório copiado: cole numa conversa ou e-mail');
                    case 'ai':
                      await _aiReport(context, s);
                    case 'data':
                      await Clipboard.setData(ClipboardData(text: exportStudent(s)));
                      app.say('Dados copiados: use "Importar" no outro aparelho');
                    case 'code':
                      await _editStudentCode(context, app, s);
                    case 'rename':
                      await _renameStudent(context, app, s);
                    case 'delete':
                      final ok = await _confirmDelete(context, 'Excluir ${s.name}?',
                          'Apaga o histórico, as tarefas e as observações deste aluno neste aparelho'
                              '${app.hasLessonWith(s.id) ? ', e descarta a aula em andamento com ele' : ''}. Não dá para desfazer.');
                      if (ok) {
                        app.removeStudent(s.id);
                        app.say('${s.name} foi excluído.');
                        if (context.mounted) Navigator.of(context).pop();
                      }
                  }
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(value: 'report', child: Text('Copiar relatório')),
                  PopupMenuItem(value: 'ai', child: Text('Relatório com IA')),
                  PopupMenuItem(value: 'data', child: Text('Copiar dados (para outro aparelho)')),
                  PopupMenuItem(value: 'code', child: Text('Código do aluno')),
                  PopupMenuItem(value: 'rename', child: Text('Renomear')),
                  PopupMenuItem(value: 'delete', child: Text('Excluir aluno')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                AppCard(child: StudentIdentity(app: app, student: s, large: true)),
                const SizedBox(height: 10),
                _summary(sum, s),
                const SizedBox(height: 10),
                _LessonCard(
                  app: app,
                  student: s,
                  onNewTask: () => _taskDialog(context, s),
                  onNewNote: () => _newNote(context, s),
                ),
                const SizedBox(height: 10),
                ValidationCard(app: app, student: s),
                _deliveryCard(context, s),
                if (tips.isNotEmpty) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Orientações do treinador', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        for (final t in tips) InsightTile(insight: t),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _tasks(context, s),
                const SizedBox(height: 10),
                _sessions(s),
                const SizedBox(height: 10),
                _notes(context, s),
                if (s.lessons.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _lessonHistory(s),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Quando há aula ou tarefas esperando envio, explica POR QUE ainda não chegaram e o que fazer.
  /// A causa mais comum: o aluno ainda não ligou o "Vínculo online" no app dele (vem desligado).
  Widget _deliveryCard(BuildContext context, Student s) {
    final waiting = s.lessons.where((r) => r.sent == false).length;
    if (waiting == 0 || s.code == null || s.linkState == 'ended') return const SizedBox.shrink();
    final issue = app.deliveryIssue[s.code];

    String title = 'Aguardando envio para ${s.name}';
    String text;
    var showInvite = false;
    var showTurnOn = false;
    if (!app.linkEnabled) {
      text = 'O vínculo online está desligado no SEU app, por isso nada sai daqui. Ligue para enviar.';
      showTurnOn = true;
    } else if (app.linkUnavailable) {
      text = 'O servidor ainda não recebe aulas. Elas ficam guardadas e vão quando ele voltar.';
    } else if (issue == 'not_ready') {
      title = '${s.name} ainda não recebeu';
      text = 'O app de ${s.name} ainda não ligou o "Vínculo online" (ele vem desligado). Sem isso o servidor não '
          'entrega nada. Peça para abrir Perfil › Vínculo online e ligar, ou mande o convite abaixo: ao abrir o '
          'link, o vínculo liga sozinho. Quando ele ligar, chega em até 30 segundos.';
      showInvite = true;
    } else if (issue == 'offline' || app.linkOnline == false) {
      text = 'Sem conexão com o servidor agora. Fica guardado e vai quando a internet voltar.';
    } else if (s.linkState != 'active') {
      text = '${s.name} ainda não está vinculado. Vai assim que o vínculo for confirmado. '
          'Se ele nunca abriu o app com o vínculo ligado, mande o convite.';
      showInvite = true;
    } else {
      text = 'Na fila. O envio é tentado a cada 30 segundos; toque em "Tentar agora" para forçar.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.schedule_send_outlined, color: AppColors.flat),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (showTurnOn)
              FilledButton.icon(
                onPressed: () => app.setLinkEnabled(true),
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: const Text('Ligar vínculo online'),
              )
            else ...[
              if (showInvite)
                FilledButton.icon(
                  onPressed: () => shareTeacherInvite(app),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Enviar convite'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  await app.syncLinks();
                  await app.flushLessons();
                  final still = s.lessons.any((r) => r.sent == false);
                  app.say(still ? 'Ainda não chegou. Veja o motivo no cartão.' : 'Enviado para ${s.name}.');
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tentar agora'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  /// Relatório pedagógico por IA. Vai só um resumo numérico, SEM nome e SEM observações.
  Future<void> _aiReport(BuildContext context, Student s) async {
    if (s.sessions.isEmpty) {
      app.say('Sem exercícios ainda: faça uma sessão com o aluno primeiro.');
      return;
    }
    if (!app.ai.consent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Relatório com IA'),
          content: const Text(
              'O app envia à IA um resumo só com números do aluno (afinação por nota, escalas e taxas de acerto). '
              'O nome e as suas observações NÃO são enviados. Nunca vai áudio.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Autorizar')),
          ],
        ),
      );
      if (ok != true) return;
      await app.ai.setConsent(true);
    }
    // Só números e tipos: texto livre (título, lição, observação) pode ter nomes e não sai do aparelho.
    final anon = Student(id: 'x', name: 'o aluno', sessions: s.sessions, tasks: [
      for (final t in s.tasks)
        t.isScale
            ? t.copyWith(note: '')
            : Assignment(id: t.id, title: t.kind.label, kind: t.kind, done: t.done, created: t.created),
    ]);
    app.ai.ask('${studentReport(anon, flats: app.flatsForText)}\n\n${buildAiPrompt(s.sessions, instrument: app.instrument.name, flats: app.flatsForText)}',
        kind: 'teacher_report');
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListenableBuilder(
          listenable: app.ai,
          builder: (c, _) {
            final ai = app.ai;
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text('Relatório de ${s.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (ai.phase == AiPhase.sending)
                  const Row(children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Expanded(child: Text('Preparando o relatório…')),
                  ])
                else if (ai.phase == AiPhase.queued)
                  Text(ai.queuePosition != null
                      ? 'Você é o ${ai.queuePosition}º da fila: sua vez em ${ai.queuedSeconds}s.'
                      : 'Muita gente usando agora: nova tentativa em ${ai.queuedSeconds}s.')
                else if (ai.phase == AiPhase.failed)
                  Text(ai.message ?? 'Não deu certo agora.', style: TextStyle(color: AppColors.sharp))
                else if (ai.lastResult != null && ai.lastKind == 'teacher_report') ...[
                  MarkdownLite(ai.lastResult!),
                  const SizedBox(height: 8),
                  Text('Gerado por IA: pode errar. Revise antes de enviar.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ai.lastResult!));
                      app.say('Relatório copiado');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar relatório'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(StudentSummary sum, Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                sum.sessions == 0 ? 'Ainda sem exercícios' : '${(sum.recentAverage! * 100).round()}% de acerto (média recente)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (sum.trendPoints != null)
              Icon(sum.trendPoints! >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: sum.trendPoints! >= 0 ? AppColors.inTune : AppColors.sharp),
          ]),
          if (sum.sessions > 0)
            Text(
              '${sum.sessions} sessões · melhor ${(sum.best! * 100).round()}% · última ${_day(sum.last!)}'
              '${sum.trendPoints == null ? '' : ' · ${sum.trendPoints! >= 0 ? '+' : ''}${sum.trendPoints!.round()} pts nas últimas 3'}',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _tasks(BuildContext context, Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Tarefas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            TextButton.icon(
              onPressed: () => _taskDialog(context, s),
              icon: const Icon(Icons.add),
              label: const Text('Nova tarefa'),
            ),
          ]),
          if (s.tasks.isEmpty)
            Text(
                'Nenhuma tarefa ainda. Toque em "Nova tarefa" para passar uma escala, uma lição de método, '
                'uma peça do repertório ou outra atividade, com observações se quiser.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          _pendingBanner(s),
          for (final t in s.tasks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => _taskDialog(context, s, edit: t),
              leading: Checkbox(value: t.done, onChanged: (_) => app.toggleAssignment(s, t.id)),
              title: Row(children: [
                Icon(_kindIcon(t.kind), size: 16, color: AppColors.textDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t.title,
                      style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null)),
                ),
              ]),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.isScale ? 'Meta ${(t.goal * 100).round()}% de acerto' : t.kind.label),
                  _sentChip(s, t),
                  _claimChip(t),
                  if (t.note.isNotEmpty)
                    Text(t.note,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textDim, fontStyle: FontStyle.italic)),
                ],
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (t.isScale && !t.done)
                  FilledButton.tonal(
                    onPressed: () => _startTask(context, s, t),
                    child: const Text('Iniciar'),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Opções da tarefa',
                  onSelected: (v) {
                    if (v == 'edit') _taskDialog(context, s, edit: t);
                    if (v == 'delete') app.removeAssignment(s, t.id);
                  },
                  itemBuilder: (c) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Apagar')),
                  ],
                ),
              ]),
            ),
        ],
      ),
    );
  }

  /// Se [s] pode receber (tem código e não encerrou o vínculo), mostra se a tarefa já foi enviada.
  Widget _sentChip(Student s, Assignment t) {
    final canReceive = s.code != null && s.linkState != 'ended';
    if (!canReceive || t.sent == null) return const SizedBox.shrink();
    // "Na fila": já empacotada, mas o servidor ainda não aceitou (sem conexão, aluno por vincular…).
    final queued = t.sent == true && s.lessons.any((r) => r.sent == false && taskIdsOf(r).contains(t.id));
    final sent = t.sent == true && !queued;
    final color = sent ? AppColors.inTune : AppColors.flat;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(sent ? Icons.mark_email_read_outlined : Icons.schedule_send_outlined, size: 13, color: color),
        const SizedBox(width: 4),
        Text(sent ? 'Enviada ao aluno' : (queued ? 'Na fila de envio' : 'A enviar'),
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  /// "O aluno marcou como feita": aguarda a validação do professor.
  Widget _claimChip(Assignment t) {
    if (!t.awaitsValidation) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.fact_check_outlined, size: 13, color: AppColors.accent),
        const SizedBox(width: 4),
        Text('Aluno marcou como feita',
            style: TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  /// "N tarefas ainda não enviadas" com o botão de enviar (fora de aula e com envio possível).
  Widget _pendingBanner(Student s) {
    final n = app.pendingTaskCount(s);
    if (n == 0 || !app.deliveryFor(s).canSend) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.flat.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.schedule_send_outlined, size: 20, color: AppColors.flat),
        const SizedBox(width: 10),
        Expanded(
          child: Text('$n tarefa${n == 1 ? '' : 's'} ainda não enviada${n == 1 ? '' : 's'} a ${s.name}.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        FilledButton.tonal(
          onPressed: () => app.say(app.sendPendingTasks(s)),
          child: const Text('Enviar'),
        ),
      ]),
    );
  }

  static IconData _kindIcon(TaskKind k) => switch (k) {
        TaskKind.scale => Icons.piano,
        TaskKind.method => Icons.menu_book_outlined,
        TaskKind.repertoire => Icons.library_music_outlined,
        TaskKind.free => Icons.edit_note,
      };

  Future<void> _startTask(BuildContext context, Student s, Assignment t) async {
    // O resultado só entra no histórico do aluno se a aula com ele estiver em andamento.
    if (!app.hasLessonWith(s.id) && app.lesson == null) {
      final start = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Começar a aula com ${s.name}?'),
          content: const Text('Em aula, o resultado do exercício entra no histórico do aluno. '
              'Sem aula, o exercício fica só no seu próprio histórico.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Só treinar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Começar a aula')),
          ],
        ),
      );
      if (start == true) app.startLesson(s);
    }
    if (!context.mounted) return;
    app.setScale(tonicPc: t.tonicPc, type: ScaleType.values[t.scaleTypeIndex], octaves: t.octaves);
    app.startExercise();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScaleExercisePage(app: app)));
  }

  /// Criar ([edit] nulo) ou editar uma tarefa, pelo formulário em tela cheia. Depois de criar,
  /// envia na hora se o professor deixou ligado e a regra de entrega permite (não precisa
  /// estar em aula); em aula, a tarefa vai junto quando a aula for encerrada.
  Future<void> _taskDialog(BuildContext context, Student s, {Assignment? edit}) async {
    final d = await openTaskForm(context, app, s, edit: edit);
    if (d == null) return;
    if (edit != null) {
      app.editAssignment(s, edit.id,
          subject: edit.isScale ? null : d.subject, detail: edit.isScale ? null : d.detail, note: d.note);
      app.say('Tarefa salva.');
      return;
    }
    final rule = app.deliveryFor(s);
    if (d.kind == TaskKind.scale) {
      app.addAssignment(s,
          title: d.title,
          scaleTypeIndex: d.scaleType.index,
          tonicPc: d.tonicPc,
          octaves: d.octaves,
          goal: d.goal,
          note: d.note);
    } else {
      app.addAssignment(s,
          title: d.title, kind: d.kind, subject: d.subject, detail: d.detail, note: d.note);
    }
    if (rule.mode == DeliveryMode.inLesson) {
      app.say('Tarefa passada. Vai para ${s.name} quando você encerrar a aula.');
    } else if (d.sendNow && rule.canSend) {
      app.say(app.sendPendingTasks(s));
    } else if (rule.mode == DeliveryMode.localOnly) {
      app.say('Tarefa passada. Fica só na sua ficha: ${s.name} ainda não pode receber.');
    } else {
      app.say('Tarefa passada. Ainda não foi enviada: use "Enviar" na ficha ou ela vai com a próxima aula.');
    }
  }

  /// Aulas já dadas a este aluno e se foram enviadas.
  Widget _lessonHistory(Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aulas dadas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          for (final l in s.lessons.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                l.sent == true ? Icons.mark_email_read_outlined : (l.sent == false ? Icons.schedule_send_outlined : Icons.phone_android),
                color: l.sent == true ? AppColors.inTune : (l.sent == false ? AppColors.flat : AppColors.textDim),
              ),
              title: Text(l.durationSec == 0
                  ? '${_day(l.endedAt)} · tarefas enviadas fora de aula'
                  : '${_day(l.endedAt)} · aula de ${fmtLessonDuration(l.durationSec)}'),
              subtitle: Text(
                '${l.taskCount} tarefa${l.taskCount == 1 ? '' : 's'}${l.noteCount > 0 ? ', ${l.noteCount} observaç${l.noteCount == 1 ? 'ão' : 'ões'}' : ''} · '
                '${l.sent == true ? 'enviada ao aluno' : (l.sent == false ? 'aguardando envio' : 'só neste aparelho')}',
                style: const TextStyle(fontSize: 12.5),
              ),
              trailing: l.sent == false
                  ? TextButton(onPressed: app.flushLessons, child: const Text('Enviar'))
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _sessions(Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Últimos exercícios', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          if (s.sessions.isEmpty)
            Text('Quando este aluno estiver "em aula", os resultados aparecem aqui.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          for (final r in s.sessions.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 44, child: Text(_day(r.date), style: TextStyle(color: AppColors.textDim))),
                Expanded(child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: (r.accuracy >= 0.8 ? AppColors.inTune : (r.accuracy >= 0.5 ? AppColors.flat : AppColors.sharp))
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${(r.accuracy * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _newNote(BuildContext context, Student s) async {
    final t = await _askText(context, 'Nova observação', 'O que anotar?', multiline: true, voice: app);
    if (t != null) app.addTeacherNote(s, t);
  }

  Widget _notes(BuildContext context, Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Observações', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            TextButton.icon(
              onPressed: () => _newNote(context, s),
              icon: const Icon(Icons.edit_note),
              label: const Text('Anotar'),
            ),
          ]),
          if (s.notes.isEmpty)
            Text('Anote pontos de atenção, elogios e combinados.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          for (final n in s.notes.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 44, child: Text(_day(n.date), style: TextStyle(color: AppColors.textDim))),
                Expanded(child: Text(n.text)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Cartão de aula na ficha do aluno: começar, pausar, retomar e encerrar. Ao encerrar, as
/// tarefas e observações passadas durante a aula vão para o aluno.
class _LessonCard extends StatefulWidget {
  final AppState app;
  final Student student;
  final VoidCallback onNewTask;
  final VoidCallback onNewNote;
  const _LessonCard({required this.app, required this.student, required this.onNewTask, required this.onNewNote});

  @override
  State<_LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<_LessonCard> {
  Timer? _tick;

  AppState get app => widget.app;
  Student get s => widget.student;

  @override
  void initState() {
    super.initState();
    // Relógio da aula: atualiza o tempo a cada segundo enquanto ela corre.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final l = app.lesson;
      if (mounted && l != null && l.studentId == s.id && !l.paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, sec = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Para onde a aula vai ao encerrar.
  String _destination() {
    if (s.code == null) {
      return 'Este aluno não tem código: a aula fica só neste aparelho. Para enviar, informe o código dele (menu ⋮ › Código do aluno).';
    }
    if (!app.linkEnabled) {
      return 'O vínculo online está desligado: a aula fica guardada e é enviada quando você ligá-lo (Meu perfil).';
    }
    if (app.linkUnavailable) return 'O servidor ainda não recebe aulas: ela fica guardada e vai quando ficar disponível.';
    if (s.linkState != 'active') {
      return 'O aluno ainda não está vinculado: a aula fica guardada e vai quando ele se vincular.';
    }
    if (app.deliveryIssue[s.code] == 'not_ready') {
      return 'O app de ${s.name} ainda não ligou o "Vínculo online": a aula fica na fila e chega assim que ele ligar. '
          'Você pode mandar um convite pela ficha.';
    }
    return 'Ao encerrar, as tarefas e observações desta aula vão para ${s.name}, em Estudo › Tarefas do professor.';
  }

  Future<void> _end() async {
    final tally = app.lessonTally();
    final l = app.lesson;
    if (l == null) return;
    final dur = fmtLessonDuration(l.elapsed(DateTime.now()).inSeconds);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Encerrar a aula?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Duração: $dur'),
            const SizedBox(height: 6),
            Text('Será enviado ao aluno: ${tally.tasks} tarefa${tally.tasks == 1 ? '' : 's'} e '
                '${tally.notes} observaç${tally.notes == 1 ? 'ão' : 'ões'}.'),
            if (tally.tasks == 0) ...[
              const SizedBox(height: 6),
              Text('Nenhuma tarefa foi passada nesta aula. Para passar uma, volte e toque em "Nova tarefa".',
                  style: TextStyle(color: AppColors.flat)),
            ],
            const SizedBox(height: 8),
            Text(_destination(), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuar aula')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Encerrar aula')),
        ],
      ),
    );
    if (ok != true) return;
    final rec = app.endLesson();
    if (rec == null) return;
    app.say(rec.sent == false
        ? 'Aula encerrada. Enviando para ${s.name}…'
        : 'Aula encerrada e guardada neste aparelho.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final l = app.lesson;
        final mine = l != null && l.studentId == s.id;
        if (!mine) {
          final other = l == null ? null : app.studentById(l.studentId);
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.school_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Aula', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                ]),
                const SizedBox(height: 4),
                Text(
                  other != null
                      ? 'Há uma aula em andamento com ${other.name}. Encerre-a para começar outra.'
                      : _destination(),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                if (other != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: other.id)),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text('Ir para a aula de ${other.name}'),
                  )
                else
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    // Primeiro confere o que o aluno marcou como feito desde a última aula.
                    await showValidationDialog(context, app, s);
                    final err = app.startLesson(s);
                    app.say(err ?? 'Aula começou. As tarefas e observações que você passar agora vão para ${s.name} ao encerrar.');
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Começar a aula'),
                ),
              ],
            ),
          );
        }
        final paused = l.paused;
        final tally = app.lessonTally();
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(paused ? Icons.pause_circle_outline : Icons.fiber_manual_record,
                    color: paused ? AppColors.flat : AppColors.sharp, size: paused ? 22 : 16),
                const SizedBox(width: 8),
                Text(paused ? 'Aula pausada' : 'Aula em andamento',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Text(_clock(l.elapsed(DateTime.now())),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 4),
              Text(
                '${tally.tasks} tarefa${tally.tasks == 1 ? '' : 's'} e ${tally.notes} observaç${tally.notes == 1 ? 'ão' : 'ões'} nesta aula até agora.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              // Atalhos: passar tarefa e anotar sem sair do cartão da aula.
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onNewTask,
                    icon: const Icon(Icons.add_task, size: 18),
                    label: const Text('Nova tarefa'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onNewNote,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Anotar'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: paused ? app.resumeLesson : app.pauseLesson,
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? 'Retomar' : 'Pausar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.sharp,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _end,
                    icon: const Icon(Icons.stop),
                    label: const Text('Encerrar'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(_destination(), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _discard,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Descartar esta aula'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Descartar a aula?'),
        content: const Text('A aula é apagada e nada é enviado ao aluno. As tarefas e observações que você já '
            'passou continuam na ficha dele.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (ok == true) {
      app.cancelLesson();
      app.say('Aula descartada.');
    }
  }
}

/// Faixa no topo da área do professor: mostra a aula em andamento (e leva até ela) ou explica
/// onde se começa uma.
class _LessonBanner extends StatefulWidget {
  final AppState app;
  const _LessonBanner({required this.app});

  @override
  State<_LessonBanner> createState() => _LessonBannerState();
}

class _LessonBannerState extends State<_LessonBanner> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final l = widget.app.lesson;
      if (mounted && l != null && !l.paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final l = app.lesson;
    final s = app.lessonStudent;
    if (l == null || s == null) {
      return AppCard(
        child: Row(children: [
          Icon(Icons.school_outlined, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Para dar uma aula, abra o aluno e toque em "Começar a aula".',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        ]),
      );
    }
    final d = l.elapsed(DateTime.now());
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0'), ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    final clock = d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss';
    return Material(
      color: AppColors.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(l.paused ? Icons.pause_circle_outline : Icons.fiber_manual_record,
                color: l.paused ? AppColors.flat : AppColors.sharp),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${l.paused ? 'Aula pausada' : 'Aula em andamento'} com ${s.name}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Text(clock, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
