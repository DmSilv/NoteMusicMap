import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'agenda_page.dart';
import 'hub_section.dart' show shareTeacherInvite;
import 'safe_input.dart';
import 'design_system.dart';
import 'teacher_setup_page.dart' show requireAdult;
import 'dictation_button.dart';
import 'dart:async';
import 'qr_scan_page.dart';
import 'person_avatar.dart';
import 'student_identity.dart';
import 'student_page.dart';
export 'student_page.dart' show StudentPage;
import 'teaching_ui.dart';
import 'materials_sheet.dart';
import 'turmas_page.dart';
import 'validation_ui.dart';
import 'hello_bar.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cadastro pelo nome: só o nome é obrigatório. O código do aluno (opcional) aparece se a pessoa tocar em
/// "Tenho o código do aluno" (ou já vem preenchido ao ler o QR). Devolve (nome, código) ou null se cancelar.
Future<(String, String?)?> _newStudentDialog(BuildContext context, AppState app, {String? code0}) async {
  final name = TextEditingController();
  final code = TextEditingController(text: code0 ?? '');
  String? nameErr, codeErr;
  var showCode = (code0 ?? '').isNotEmpty;
  final r = await showDialog<(String, String?)>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(tr('Cadastrar pelo nome')),
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
                  labelText: tr('Nome do aluno'),
                  errorText: nameErr,
                  suffixIcon: DictationButton(app: app, controller: name),
                ),
              ),
              const SizedBox(height: Ds.s12),
              if (!showCode)
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
                  onPressed: () => setS(() => showCode = true),
                  icon: const Icon(Icons.pin_outlined, size: 18),
                  label: Text(tr('Tenho o código do aluno')),
                )
              else
                TextField(
                  controller: code,
                  inputFormatters: codeFormatters,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: tr('Código do aluno'),
                    hintText: 'K7QM-4TXD',
                    helperText: tr('Digite o código ou leia o QR do aluno.'),
                    helperMaxLines: 3,
                    errorText: codeErr,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(
                      tooltip: tr('Ler QR do aluno'),
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final s = await scanShareCode(c,
                            title: tr('Ler QR do aluno'),
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
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar'))),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
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
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('Adicionar')),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  code.dispose();
  return r;
}

/// Cadastra pelo nome e já abre a ficha do aluno (o próximo passo é passar uma tarefa ou marcar a aula).
Future<void> _addByName(BuildContext context, AppState app, {String? code0}) async {
  final r = await _newStudentDialog(context, app, code0: code0);
  if (r == null) return;
  final s = app.addStudent(r.$1, code: r.$2);
  app.say(tr('{0} foi adicionado à sua lista.', [s.name]));
  if (context.mounted) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id)));
}

/// Lê o QR do aluno (ele mostra no perfil dele) e cadastra com o código já preenchido.
Future<void> _scanAndAddStudent(BuildContext context, AppState app) async {
  final s = await scanShareCode(context,
      title: tr('Ler QR do aluno'), want: 'aluno', check: (code) => app.checkStudent('aluno', code).code, onCamera: app.setCameraStatus);
  if (s == null || !context.mounted) return;
  await _addByName(context, app, code0: s.code);
}

/// UM só lugar para adicionar aluno, com três caminhos claros. É o que abre em todo botão "Adicionar aluno".
Future<void> showAddStudent(BuildContext context, AppState app) {
  Widget option(BuildContext c, {required IconData icon, required String title, required String sub, required VoidCallback onTap, bool main = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Ds.s12),
        child: Material(
          color: main ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surface2,
          borderRadius: BorderRadius.circular(Ds.radiusCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(Ds.radiusCard),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.all(Ds.s16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Ds.radiusCard), border: Border.all(color: main ? AppColors.accent : AppColors.outline, width: main ? 2 : 1)),
              child: Row(children: [
                DsIconBadge(icon, size: 44),
                const SizedBox(width: Ds.s16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: Ds.s4),
                    Text(sub, style: Ds.support()),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
              ]),
            ),
          ),
        ),
      );
  return showDsSheet(
    context,
    title: tr('Adicionar aluno'),
    listenable: app,
    children: (c) => [
      option(
        c,
        main: true,
        icon: Icons.send_rounded,
        title: tr('Enviar convite'),
        sub: tr('Mande o link por mensagem. Quando o aluno abrir, ele aparece aqui sozinho.'),
        onTap: () {
          Navigator.of(c).pop();
          shareTeacherInvite(app);
        },
      ),
      option(
        c,
        icon: Icons.qr_code_scanner_rounded,
        title: tr('Ler o QR do aluno'),
        sub: tr('O aluno está com você: aponte a câmera para o QR do perfil dele.'),
        onTap: () {
          Navigator.of(c).pop();
          _scanAndAddStudent(context, app);
        },
      ),
      option(
        c,
        icon: Icons.person_add_alt_1_rounded,
        title: tr('Cadastrar pelo nome'),
        sub: tr('Só o nome. O código e o vínculo você coloca depois.'),
        onTap: () {
          Navigator.of(c).pop();
          _addByName(context, app);
        },
      ),
    ],
  );
}

/// Chamado ao abrir o app por um link/QR de aluno (`?aluno=K7QM-4TXD`): leva o
/// professor direto ao cadastro, com o código já preenchido.
Future<void> handleIncomingStudentCode(BuildContext context, AppState app) async {
  final code = app.incomingStudentCode;
  if (code == null) return;
  app.incomingStudentCode = null;
  final known = app.studentByCode(code);
  if (known != null) {
    app.say(tr('{0} já está na sua lista.', [known.name]));
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
        title: Text(tr('Código de aluno recebido')),
        content: Text(tr('O código {0} foi lido. Para cadastrar e acompanhar este aluno, ligue o modo professor (você continua usando o app normalmente como aluno).', [code])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ligar e adicionar'))),
        ],
      ),
    );
    if (on != true || !context.mounted) return;
    if (!await requireNickname(context, app, reason: tr('Para ser professor, seus alunos precisam ver o seu nome.'))) return;
    if (!context.mounted || !await requireAdult(context, app)) return;
    if (!context.mounted) return;
    app.setTeacherMode(true);
  }
  final r = await _newStudentDialog(context, app, code0: code);
  if (r != null) {
    app.addStudent(r.$1, code: r.$2);
    app.say(tr('{0} foi adicionado à sua lista.', [r.$1]));
  }
}

/// Guia curto e didático do que a área do professor faz, aberto no primeiro acesso.
class _HowItWorks extends StatelessWidget {
  final bool open;
  const _HowItWorks({required this.open});

  static final _steps = <(IconData, String, String)>[
    (
      Icons.person_add_alt_1,
      tr('1. Cadastre o aluno'),
      tr('Mais rápido: peça ao aluno para abrir o perfil dele (ícone no topo do app) e aponte a câmera do seu celular para o QR. O Notemusic abre já com o código e você só confirma o nome. Também dá para digitar o código (algo como K7QM-4TXD) em "Adicionar aluno", ou cadastrar só pelo nome e colocar o código depois, no menu do aluno. Não precisa de e-mail nem de cadastro completo.')
    ),
    (
      Icons.play_circle_outline,
      tr('2. Comece a aula'),
      tr('Abra o aluno e toque em "Começar a aula". Enquanto ela durar, cada exercício feito no app entra no histórico desse aluno, e não no seu. Dá para pausar e, ao encerrar, o que você passou vai para o aluno.')
    ),
    (
      Icons.assignment_outlined,
      tr('3. Passe tarefas'),
      tr('Abra o aluno e toque em "Nova tarefa". Escolha o tipo: escala ou arpejo (com meta de acerto, concluída sozinha), método e lição (ex.: Suzuki · Lição 5), repertório ou outra atividade. Em todas há um campo de observações para o que merece atenção; use o microfone do teclado para ditar. Toque numa tarefa para editar.')
    ),
    (
      Icons.insights,
      tr('4. Acompanhe a evolução'),
      tr('Na página do aluno você vê a média, o melhor resultado, a tendência e orientações automáticas sobre as notas que ele mais desafina. Use "Anotar" para registrar suas observações.')
    ),
    (
      Icons.ios_share,
      tr('5. Compartilhe'),
      tr('No menu ⋮ do aluno: "Copiar relatório" (para enviar por mensagem ou e-mail), "Relatório com IA" e "Copiar dados" para levar o aluno a outro aparelho (use "Importar dados de um aluno" lá).')
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
          title: Text(tr('Como funciona'), style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(tr('Cadastrar, acompanhar e compartilhar, passo a passo'),
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
              child: Text(
                tr('Vínculo online: quando você lê o QR do aluno (ou ele lê o seu), o vínculo aparece nos dois aparelhos em poucos segundos. O aluno que ler o seu QR entra sozinho na sua lista, e você entra na lista de professores dele. Qualquer um pode encerrar o vínculo quando quiser. Funciona com o "Vínculo online" ligado (no perfil de cada um).\n\nAulas: na ficha do aluno, toque em "Começar a aula". Passe as tarefas e observações normalmente e, ao tocar em "Encerrar", tudo o que você passou naquela aula vai para o aluno, em Minha conta › Minhas aulas. Dá para pausar. O histórico de exercícios do aluno continua só no aparelho dele e no seu.'),
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

  /// Filtro por turma (null = todas).
  String? _turmaFilter;

  bool _matches(Student s) {
    if (_turmaFilter != null && s.turma != _turmaFilter) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) || (s.code ?? '').toLowerCase().contains(q.replaceAll('-', ''));
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    if (n == 0) return;
    final ok = await confirmDelete(
        context,
        n == 1 ? tr('Excluir 1 aluno?') : tr('Excluir {0} alunos?', [n]),
        tr('Apaga o histórico, as tarefas e as observações {0} neste aparelho{1}. Não dá para desfazer.', [n == 1 ? tr('deste aluno') : tr('destes alunos'), _selected.any(app.hasLessonWith) ? tr(', e descarta a aula em andamento') : '']));
    if (!ok) return;
    final removed = app.removeStudents(Set.of(_selected));
    setState(() {
      _selected.clear();
      _manage = false;
    });
    app.say(removed == 1 ? tr('Aluno excluído.') : tr('{0} alunos excluídos.', [removed]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Alunos')),
        actions: [
          HelpButton(
            title: tr('Como funciona'),
            sections: [for (final (_, t, x) in _HowItWorks._steps) (t, x)],
          ),
          IconButton(
            tooltip: tr('Agenda do professor'),
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AgendaPage(app: app))),
          ),
          // O que não é do dia a dia fica num menu: ler QR, importar, métodos e a senha da tela.
          ListenableBuilder(
            listenable: app,
            builder: (context, _) => app.teacherLocked
                ? const SizedBox.shrink()
                : PopupMenuButton<String>(
                    tooltip: tr('Mais opções'),
                    onSelected: (v) {
                      switch (v) {
                        case 'import':
                          _importStudent(context);
                        case 'methods':
                          showMaterialsSheet(context, app);
                        case 'turmas':
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TurmasPage(app: app)));
                        case 'pin':
                          _setPin(context);
                      }
                    },
                    itemBuilder: (c) => [
                      PopupMenuItem(value: 'import', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.download), title: Text(tr('Importar aluno')))),
                      PopupMenuItem(
                        value: 'methods',
                        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.library_books_outlined), title: Text(tr('Métodos e repertório'))),
                      ),
                      PopupMenuItem(value: 'turmas', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.workspaces_outline), title: Text(tr('Turmas')))),
                      PopupMenuItem(
                        value: 'pin',
                        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(app.teacherPinHash == null ? Icons.lock_open : Icons.lock_outline), title: Text(app.teacherPinHash == null ? tr('Senha desta tela') : tr('Trocar ou remover a senha'))),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: app,
        // Lista vazia: o botão grande do centro já pede o 1º aluno; o flutuante só entra quando há alunos.
        builder: (context, _) => app.teacherLocked || _manage || app.students.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: () => showAddStudent(context, app),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(tr('Adicionar aluno'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
      ),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => app.teacherLocked ? _PinGate(app: app) : _home(context),
        ),
      ),
    );
  }

  Widget _home(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      children: [
        LessonBanner(app: app),
        const SizedBox(height: 10),
        _summaryStrip(),
        if (app.turmas.isEmpty && app.students.length >= 3 && !app.turmaHintOff)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DsCardTitle(Icons.workspaces_outline, tr('Organize por turmas'), subtitle: tr('Separe seus alunos por grupo e passe a mesma tarefa para todos.')),
                const SizedBox(height: Ds.s12),
                Row(children: [
                  FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TurmasPage(app: app))), child: Text(tr('Criar turmas'))),
                  const SizedBox(width: Ds.s8),
                  TextButton(onPressed: app.hideTurmaHint, child: Text(tr('Agora não'))),
                ]),
              ]),
            ),
          ),
        if (app.turmas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(label: Text(tr('Todas')), selected: _turmaFilter == null, onSelected: (_) => setState(() => _turmaFilter = null)),
                for (final t in app.turmas) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(label: Text(t.name), selected: _turmaFilter == t.id, onSelected: (v) => setState(() => _turmaFilter = v ? t.id : null)),
                ],
              ]),
            ),
          ),
        if (app.students.length > 5)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _search,
              inputFormatters: const [SafeText.name()],
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Buscar aluno por nome ou código'),
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
                  child: Text(tr('Selecionar todos')),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_selected.isEmpty ? tr('Excluir') : tr('Excluir ({0})', [_selected.length])),
                ),
              ],
            ),
          ),
        ..._groupedList(context),
        if (app.students.isNotEmpty && !app.students.any(_matches))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(tr('Nenhum aluno encontrado.'),
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ),
        if (app.students.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Ds.s32),
            child: Column(children: [
              Icon(Icons.groups_outlined, size: 44, color: AppColors.textDim),
              const SizedBox(height: Ds.s12),
              Text(tr('Nenhum aluno ainda.'), style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700)),
              const SizedBox(height: Ds.s16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.primaryHeight)),
                onPressed: () => showAddStudent(context, app),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(tr('Adicionar aluno')),
              ),
            ]),
          ),
      ],
    );
  }

  Future<void> _importStudent(BuildContext context) async {
    final t = await askText(context, tr('Importar aluno'), tr('Cole aqui os dados copiados do outro aparelho'), multiline: true, action: tr('Importar'));
    if (t != null && t.trim().isNotEmpty) app.say(app.importStudentText(t));
  }

  Future<void> _setPin(BuildContext context) async {
    final pin = await askText(context, tr('Trava com senha (opcional)'), tr('Senha de 4 números (vazio remove)'), action: tr('Definir'));
    if (pin == null) return;
    final p = pin.trim();
    if (p.isEmpty) {
      app.setTeacherPin(null);
      app.say(tr('Trava removida'));
    } else if (RegExp(r'^\d{4}$').hasMatch(p)) {
      app.setTeacherPin(p);
      app.say(tr('Trava definida: peça a senha ao abrir esta área'));
    } else {
      app.say(tr('Use exatamente 4 números'));
    }
  }

  /// Os alunos em grupos, do mais urgente ao resto: aula hoje, tarefas para validar e os demais. Cada aluno aparece uma vez.
  List<Widget> _groupedList(BuildContext context) {
    final now = DateTime.now();
    bool hasClassToday(Student s) {
      final o = s.code == null ? null : nextOccurrence(app.slotsOf(s.code!), now.millisecondsSinceEpoch);
      return o != null && o.start.year == now.year && o.start.month == now.month && o.start.day == now.day;
    }

    final all = app.students.where(_matches).toList();
    final today = <Student>[], waiting = <Student>[], rest = <Student>[];
    for (final s in all) {
      if (hasClassToday(s)) {
        today.add(s);
      } else if (app.awaitingOf(s).isNotEmpty) {
        waiting.add(s);
      } else {
        rest.add(s);
      }
    }
    final groups = <(String, IconData, List<Student>)>[
      (tr('Aula hoje'), Icons.event_available_outlined, today),
      (tr('Para validar'), Icons.fact_check_outlined, waiting),
      (today.isEmpty && waiting.isEmpty ? '' : tr('Todos os outros'), Icons.groups_outlined, rest),
    ].where((g) => g.$3.isNotEmpty).toList();
    return [
      for (final g in groups) ...[
        if (g.$1.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
            child: Row(children: [
              Icon(g.$2, size: 16, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text('${g.$1} · ${g.$3.length}', style: Ds.section()),
            ]),
          ),
        for (final s in g.$3) _studentCard(context, s),
      ],
    ];
  }

  /// Faixa de números do topo: quantos alunos, quantas tarefas esperam validação e aulas de hoje.
  Widget _summaryStrip() {
    final today = classesToday(app.visibleAgenda, DateTime.now()).count;
    final waiting = app.awaitingTotal;
    Widget chip(IconData icon, String text, {bool alert = false, VoidCallback? onTap}) {
      final color = alert ? AppColors.accent : AppColors.textDim;
      final box = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: alert ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: alert ? 0.6 : 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
      return onTap == null
          ? box
          : InkWell(
              borderRadius: BorderRadius.circular(Ds.tap / 2),
              onTap: onTap,
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: Ds.tap), child: Center(widthFactor: 1, child: box)),
            );
    }

    final n = app.students.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: [
        chip(Icons.groups_outlined, n == 1 ? tr('1 aluno') : tr('{0} alunos', [n])),
        if (waiting > 0)
          chip(Icons.fact_check_outlined, tr('{0} para validar', [waiting]),
              alert: true, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ValidationQueuePage(app: app)))),
        if (today > 0) chip(Icons.event_outlined, today == 1 ? tr('1 aula hoje') : tr('{0} aulas hoje', [today])),
        ])),
        if (n > 0 && !app.teacherLocked)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap), padding: const EdgeInsets.symmetric(horizontal: Ds.s8)),
            onPressed: () => setState(() {
              _manage = !_manage;
              _selected.clear();
            }),
            icon: Icon(_manage ? Icons.check : Icons.checklist, size: 20),
            label: Text(_manage ? tr('Concluir') : tr('Gerenciar')),
          ),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _studentCard(BuildContext context, Student s) {
    final sum = summarizeStudent(s);
    final open = s.tasks.where((t) => !t.done).length;
    final awaiting = app.awaitingOf(s).length;
    final nowD = DateTime.now();
    final nextOcc = s.code == null ? null : nextOccurrence(app.slotsOf(s.code!), nowD.millisecondsSinceEpoch);
    final classToday = nextOcc != null && nextOcc.start.year == nowD.year && nextOcc.start.month == nowD.month && nextOcc.start.day == nowD.day;
    final absences = absencesSince(s.absences, sinceMs: nowD.millisecondsSinceEpoch - 60 * kMsDay);
    final hm = nextOcc == null ? '' : '${nextOcc.start.hour.toString().padLeft(2, '0')}:${nextOcc.start.minute.toString().padLeft(2, '0')}';
    final subtitle = nextOcc != null
        ? (classToday ? tr('Aula hoje às {0}', [hm]) : tr('Próxima aula: {0}', [fmtSlotWhen(nextOcc.start, nowD)]))
        : (sum.sessions == 0 ? tr('Sem aula marcada') : tr('{0} sessões · média {1}%', [sum.sessions, (sum.recentAverage! * 100).round()]));
    final ring = classToday ? AppColors.accent : (awaiting > 0 ? AppColors.accent : Colors.transparent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _manage
              ? () => setState(() => _selected.contains(s.id) ? _selected.remove(s.id) : _selected.add(s.id))
              : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id))),
          child: Row(
            children: [
              if (_manage)
                Checkbox(
                  value: _selected.contains(s.id),
                  onChanged: (v) => setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                )
              else
                PersonAvatar(name: s.name, photo: app.photoOfStudent(s), tint: studentTint(s), radius: 23, ring: ring == Colors.transparent ? null : ring),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(app.labelOf(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5))),
                      const SizedBox(width: 8),
                      linkBadge(s),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      if (nextOcc != null) ...[
                        Icon(Icons.event_outlined, size: 14, color: classToday ? AppColors.accent : AppColors.textDim),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: classToday ? AppColors.accent : AppColors.textDim, fontSize: 13, fontWeight: classToday ? FontWeight.w700 : FontWeight.w400)),
                      ),
                    ]),
                    if (awaiting > 0 || open > 0 || absences > 0 || s.instrument != null || app.turmaOf(s) != null) ...[
                      const SizedBox(height: 7),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (s.instrument != null) _tag(teachingById(s.instrument)?.label ?? '', AppColors.textDim),
                        if (app.turmaOf(s) != null) _tag(app.turmaOf(s)!.name, AppColors.textDim),
                        if (awaiting > 0) _tag(tr('{0} para validar', [awaiting]), AppColors.accent),
                        if (open > 0) _tag(tr('{0} em aberto', [open]), AppColors.flat),
                        if (absences > 0) _tag(tr('{0} falta{1}', [absences, absences == 1 ? '' : 's']), AppColors.sharp),
                      ]),
                    ],
                  ],
                ),
              ),
              if (!_manage)
                PopupMenuButton<String>(
                  tooltip: tr('Opções de {0}', [app.labelOf(s)]),
                  icon: Icon(Icons.more_vert, color: AppColors.textDim),
                  onSelected: (v) async {
                    switch (v) {
                      case 'open':
                        await Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: s.id)));
                      case 'rename':
                        await renameStudent(context, app, s);
                      case 'code':
                        await editStudentCode(context, app, s);
                      case 'instrument':
                        await showStudentInstrumentSheet(context, app, s);
                      case 'delete':
                        final ok = await confirmDelete(context, tr('Excluir {0}?', [app.labelOf(s)]),
                            tr('Apaga o histórico, as tarefas e as observações deste aluno neste aparelho{0}. Não dá para desfazer.', [app.hasLessonWith(s.id) ? tr(', e descarta a aula em andamento com ele') : '']));
                        if (ok) {
                          app.removeStudent(s.id);
                          app.say(tr('{0} foi excluído.', [s.name]));
                        }
                    }
                  },
                  itemBuilder: (c) => [
                    PopupMenuItem(value: 'open', child: Text(tr('Abrir'))),
                    PopupMenuItem(value: 'rename', child: Text(tr('Renomear'))),
                    PopupMenuItem(value: 'code', child: Text(tr('Código do aluno'))),
                    PopupMenuItem(value: 'instrument', child: Text(tr('Instrumento do aluno'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Excluir aluno'))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
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
      setState(() => _error = tr('Senha incorreta'));
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
            Text(tr('Alunos protegidos'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr('Digite a senha de 4 números.'), style: TextStyle(color: AppColors.textDim)),
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
