import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../ai/coach_ai.dart';
import 'markdown_lite.dart';
import 'scale_exercise_page.dart';
import 'theme.dart';
import 'widgets.dart';

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

Future<String?> _askText(BuildContext context, String title, String label,
    {String initial = '', bool multiline = false, String action = 'Salvar'}) async {
  final ctl = TextEditingController(text: initial);
  final v = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
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
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Nome do aluno', errorText: nameErr),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Código do aluno (opcional)',
                  hintText: 'K7QM-4TXD',
                  helperText: 'O aluno vê o código em Configurações › Meu perfil.',
                  helperMaxLines: 2,
                  errorText: codeErr,
                  errorMaxLines: 3,
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
              final e = app.checkStudentCode(code.text);
              if (n.isEmpty || e != null) {
                setS(() {
                  nameErr = n.isEmpty ? 'Digite o nome do aluno' : null;
                  codeErr = e;
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
  if (code == app.profile.shareCode) {
    app.say('Este é o seu próprio código.');
    return;
  }
  final known = app.studentByCode(code);
  if (known != null) {
    app.say('${known.name} já está na sua lista.');
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
      '2. Escolha quem está em aula',
      'Em "Aluno em aula agora" toque no nome. Cada exercício feito no app entra no histórico '
          'desse aluno, e não no seu.'
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
                'Hoje: o código identifica o aluno na sua lista e tudo fica neste aparelho; o aluno ainda '
                'não vê suas tarefas e orientações no app dele.\n\n'
                'Em breve: ao digitar o código, o aluno recebe o seu pedido de acompanhamento, aceita, e '
                'passa a ver no próprio app as tarefas, as suas orientações e o histórico dele. Nada é '
                'compartilhado sem o aluno aceitar, e ele pode encerrar quando quiser.',
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

  /// Modo "Gerenciar": caixas de seleção para excluir vários alunos.
  bool _manage = false;
  final Set<String> _selected = {};
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
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
            'neste aparelho. Não dá para desfazer.');
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
        title: const Text('Área do professor'),
        actions: [
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
    final active = app.activeStudent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.school_outlined),
                SizedBox(width: 8),
                Expanded(
                    child: Text('Acompanhe seus alunos',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              Text(
                'Cadastre os alunos, escolha quem está em aula e, a cada exercício, o resultado vai para o '
                'histórico dele. Passe tarefas, anote observações e gere relatórios. Tudo fica neste aparelho; '
                'para levar os dados a outro aparelho, use copiar e importar.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _HowItWorks(open: app.students.isEmpty),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aluno em aula agora', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                active == null
                    ? 'Nenhum aluno escolhido: os exercícios ficam no seu próprio histórico.'
                    : 'Os exercícios feitos agora ficam no histórico de ${active.name}.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ChoiceChip(
                  label: const Text('Ninguém'),
                  selected: active == null,
                  onSelected: (_) => app.setActiveStudent(null),
                ),
                for (final s in app.students)
                  ChoiceChip(
                    label: Text(s.name),
                    selected: active?.id == s.id,
                    onSelected: (_) => app.setActiveStudent(s.id),
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (app.students.length > 5)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _search,
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
            child: Text('Nenhum aluno ainda. Toque em "Novo aluno" para começar.',
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
                      Text('Código ${s.code}',
                          style: TextStyle(color: AppColors.textDim, fontSize: 12, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      sum.sessions == 0
                          ? 'Sem exercícios ainda'
                          : '${sum.sessions} sessões · média ${(sum.recentAverage! * 100).round()}% · última ${_day(sum.last!)}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
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
                            'Apaga o histórico, as tarefas e as observações deste aluno neste aparelho. '
                                'Não dá para desfazer.');
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
  final n = await _askText(context, 'Renomear', 'Nome', initial: s.name);
  if (n != null && n.trim().isNotEmpty) {
    s.name = n.trim();
    app.setActiveStudent(app.activeStudentId); // salva e atualiza
  }
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
            const Text('Área do professor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
        final tips = analyzePractice(s.sessions, flats: app.preferFlats).take(4).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(s.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'report':
                      await Clipboard.setData(ClipboardData(text: studentReport(s, flats: app.preferFlats)));
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
                          'Apaga o histórico, as tarefas e as observações deste aluno neste aparelho. '
                              'Não dá para desfazer.');
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
                _summary(sum, s),
                const SizedBox(height: 10),
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
              ],
            ),
          ),
        );
      },
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
    app.ai.ask('${studentReport(anon, flats: app.preferFlats)}\n\n${buildAiPrompt(s.sessions, instrument: app.instrument.name, flats: app.preferFlats)}',
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
                  Text('Gerado por IA${ai.provider == null ? '' : ' (${ai.provider})'}: pode errar. Revise antes de enviar.',
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
    final active = app.activeStudentId == s.id;
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
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: active ? null : () => app.setActiveStudent(s.id),
            icon: Icon(active ? Icons.check_circle : Icons.play_circle_outline),
            label: Text(active ? 'Em aula agora' : 'Começar aula com ${s.name}'),
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

  static IconData _kindIcon(TaskKind k) => switch (k) {
        TaskKind.scale => Icons.piano,
        TaskKind.method => Icons.menu_book_outlined,
        TaskKind.repertoire => Icons.library_music_outlined,
        TaskKind.free => Icons.edit_note,
      };

  void _startTask(BuildContext context, Student s, Assignment t) {
    app.setActiveStudent(s.id);
    app.setScale(tonicPc: t.tonicPc, type: ScaleType.values[t.scaleTypeIndex], octaves: t.octaves);
    app.startExercise();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScaleExercisePage(app: app)));
  }

  /// Criar ([edit] nulo) ou editar uma tarefa. Quatro tipos: escala/arpejo (medida
  /// pelo app), método e lição, repertório e outra atividade. Todos aceitam
  /// uma observação livre.
  Future<void> _taskDialog(BuildContext context, Student s, {Assignment? edit}) async {
    var kind = edit?.kind ?? TaskKind.scale;
    var type = edit != null && edit.isScale ? ScaleType.values[edit.scaleTypeIndex] : app.scaleType;
    var pc = edit != null && edit.isScale ? edit.tonicPc : app.scaleTonicMidi % 12;
    var oct = edit?.octaves ?? 1;
    var goal = edit?.goal ?? 0.8;
    final names = app.cfg.copyWith(transpose: 0);
    final subject = TextEditingController(text: edit?.subject ?? '');
    final detail = TextEditingController(text: edit?.detail ?? '');
    final note = TextEditingController(text: edit?.note ?? '');
    String? subjectErr;
    final isEdit = edit != null;
    final methods = [
      ...app.recentMethods(),
      for (final m in kMethodSuggestions)
        if (!app.recentMethods().contains(m)) m
    ];

    String subjectLabel() => switch (kind) {
          TaskKind.method => 'Método ou livro',
          TaskKind.repertoire => 'Peça ou obra',
          _ => 'O que estudar',
        };
    String? detailLabel() => switch (kind) {
          TaskKind.method => 'Lição ou exercício (ex.: Lição 5)',
          TaskKind.repertoire => 'Trecho ou compassos (opcional)',
          _ => null,
        };

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(isEdit ? 'Editar tarefa' : 'Nova tarefa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEdit) ...[
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final k in TaskKind.values)
                      ChoiceChip(
                        avatar: Icon(_kindIcon(k), size: 16),
                        label: Text(k.label),
                        selected: kind == k,
                        onSelected: (_) => setS(() => kind = k),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
                if (kind == TaskKind.scale) ...[
                  if (isEdit)
                    Text(edit.title, style: const TextStyle(fontWeight: FontWeight.w800))
                  else ...[
                    PickerField<ScaleType>(
                      label: 'Escala ou arpejo',
                      value: type,
                      options: [for (final t in ScaleType.values) OptionItem(t, t.label)],
                      onChanged: (v) => setS(() => type = v),
                    ),
                    const SizedBox(height: 10),
                    const Text('Nota inicial'),
                    Wrap(spacing: 5, runSpacing: 2, children: [
                      for (var i = 0; i < 12; i++)
                        ChoiceChip(
                          label: Text(noteName(i + 60, names)),
                          selected: pc == i,
                          onSelected: (_) => setS(() => pc = i),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    const Text('Oitavas'),
                    Wrap(spacing: 6, children: [
                      for (final o in [1, 2, 3])
                        ChoiceChip(label: Text('$o'), selected: oct == o, onSelected: (_) => setS(() => oct = o)),
                    ]),
                    const SizedBox(height: 10),
                    const Text('Meta de acerto'),
                    Wrap(spacing: 6, children: [
                      for (final g in [0.6, 0.7, 0.8, 0.9])
                        ChoiceChip(
                            label: Text('${(g * 100).round()}%'),
                            selected: goal == g,
                            onSelected: (_) => setS(() => goal = g)),
                    ]),
                  ],
                ] else ...[
                  TextField(
                    controller: subject,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: subjectLabel(), errorText: subjectErr),
                    onChanged: (_) {
                      if (subjectErr != null) setS(() => subjectErr = null);
                    },
                  ),
                  if (kind == TaskKind.method) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 0, children: [
                      for (final m in methods.take(8))
                        ActionChip(
                          label: Text(m),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setS(() {
                            subject.text = m;
                            subjectErr = null;
                          }),
                        ),
                    ]),
                  ],
                  if (detailLabel() != null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: detail,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: detailLabel()),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                    alignLabelWithHint: true,
                    helperText: 'O que merece atenção ou estudar mais. Dica: toque no microfone do teclado para ditar.',
                    helperMaxLines: 3,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (kind != TaskKind.scale && subject.text.trim().isEmpty) {
                  setS(() => subjectErr = 'Escreva o que o aluno vai estudar');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: Text(isEdit ? 'Salvar' : 'Passar tarefa'),
            ),
          ],
        ),
      ),
    );
    final subjectText = subject.text, detailText = detail.text, noteText = note.text;
    subject.dispose();
    detail.dispose();
    note.dispose();
    if (ok != true) return;
    if (isEdit) {
      app.editAssignment(s, edit.id,
          subject: edit.isScale ? null : subjectText, detail: edit.isScale ? null : detailText, note: noteText);
    } else if (kind == TaskKind.scale) {
      app.addAssignment(s,
          title: '${type.display(noteName(pc + 60, names))} · $oct oitava${oct > 1 ? 's' : ''}',
          scaleTypeIndex: type.index,
          tonicPc: pc,
          octaves: oct,
          goal: goal,
          note: noteText);
    } else {
      app.addAssignment(s,
          title: Assignment.titleFor(subjectText, detailText),
          kind: kind,
          subject: subjectText,
          detail: detailText,
          note: noteText);
    }
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

  Widget _notes(BuildContext context, Student s) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Observações', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            TextButton.icon(
              onPressed: () async {
                final t = await _askText(context, 'Nova observação', 'O que anotar?', multiline: true);
                if (t != null) app.addTeacherNote(s, t);
              },
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
