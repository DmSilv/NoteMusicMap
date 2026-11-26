import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import 'account_email.dart';
import 'account_explainer.dart';
import 'my_lessons_page.dart';
import 'plan_page.dart';
import 'safe_input.dart';
import '../link/link_service.dart' show LinkedPerson;
import 'qr_scan_page.dart';
import 'settings_page.dart' show SettingsPage, showResetSheet;
import 'share_sheet.dart' show shareLink, showShareSheet;
import 'teacher_page.dart';
import 'hello_bar.dart';
import 'link_bar.dart';
import 'cloud_copy_body.dart';
import 'design_system.dart';
import 'devices_page.dart';
import 'join_account_page.dart';
import 'person_avatar.dart';
import 'recovery_help_page.dart';
import 'photo_pick.dart';
import 'teacher_setup_page.dart' show requireAdult;
import 'teaching_ui.dart';
import 'materials_sheet.dart';
import 'turmas_page.dart';
import 'hub_section.dart' show shareStudentLink;
import 'theme.dart';
import 'widgets.dart';

/// "Minha conta": lista curta com o código que identifica você (sem cadastro) e a chave de
/// recuperação, que permite levar o histórico para outro aparelho.
class ProfilePage extends StatefulWidget {
  final AppState app;

  /// Mantido por compatibilidade: a tela agora é uma lista só (sem abas).
  final int initialTab;
  const ProfilePage({super.key, required this.app, this.initialTab = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _showShort = false; // mostrar a chave de 25 na tela
  bool _keyBusy = false;
  bool _fast = false;
  final _restore = TextEditingController();
  final _claimCode = TextEditingController();
  final _claimSupport = TextEditingController();
  bool _claiming = false;
  late final TextEditingController _name = TextEditingController(
    text: widget.app.profile.name ?? '',
  );

  AppState get app => widget.app;

  /// O nome só muda de propósito: fica travado (só leitura) e o botão "Alterar" abre a edição. Sem nome ainda, já abre editável.
  late bool _editingName = app.needsNickname;

  bool get _nameLocked => !_editingName;

  /// Quem já está vinculado (professor ou aluno) é avisado de que o nome muda para essas pessoas.
  Future<void> _askEditName() async {
    final linked = app.myTeachers.isNotEmpty || app.students.any((s) => s.code != null);
    if (linked) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(Icons.badge_outlined, color: AppColors.textDim),
          title: Text(tr('Alterar o seu nome?')),
          content: Text(tr('Seus professores e alunos vinculados vão ver o nome novo.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Alterar'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _upd(() => _editingName = true);
  }

  void _saveName() {
    final v = _name.text.trim();
    if (v.isEmpty) {
      app.say(tr('O nome não pode ficar vazio.'));
      return;
    }
    app.setProfileName(v);
    _upd(() => _editingName = false);
  }

  void _cancelName() {
    _name.text = app.profile.name ?? '';
    _upd(() => _editingName = false);
  }

  @override
  void initState() {
    super.initState();
    // Atualiza os vínculos enquanto esta tela está aberta. Quem ainda não tem professor consulta
    // mais depressa (10 s): é quem espera um professor adicioná-lo.
    _fast = app.myTeachers.isEmpty;
    app.watchLinks(fast: _fast);
    app.markTab('profile');
    unawaited(app.refreshEmailStatus()); // o e-mail da conta só aparece se o servidor tiver o envio ligado
  }

  @override
  void dispose() {
    app.unwatchLinks(fast: _fast);
    _restore.dispose();
    _claimCode.dispose();
    _claimSupport.dispose();
    _tick.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    app.say(tr('{0} copiado.', [what]));
  }

  /// Gera (ou troca) a chave de recuperação de 25 caracteres.
  Future<void> _genKey() async {
    if (app.hasRecoveryKey) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Gerar outra chave?')),
          content: Text(tr('A chave atual deixa de valer. Guarde a nova em lugar seguro.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Gerar'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _upd(() => _keyBusy = true);
    final problem = await app.recoveryKeyNew();
    if (!mounted) return;
    _upd(() {
      _keyBusy = false;
      if (problem == null) _showShort = true;
    });
    app.say(problem ?? tr('Chave gerada. Guarde em lugar seguro.'));
  }

  /// "Como funciona": para que serve a chave, onde guardar e o que fazer ao trocar de celular (sem e-mail no meio).
  Widget _howKeyCard() {
    final steps = <(IconData, String, String)>[
      (Icons.shield_outlined, tr('A chave é a sua cópia de segurança'), tr('Ela não chega por e-mail: aparece só aqui. Sem ela e sem outro aparelho, a conta não volta.')),
      (Icons.save_alt, tr('Onde guardar'), tr('No gerenciador de senhas, nas notas do celular ou em papel. Não envie para ninguém.')),
      (Icons.phone_android, tr('Trocou de celular?'), tr('No novo, abra o app e toque em Entrar na minha conta › Tenho a chave.')),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Como funciona'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s12),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsIconBadge(s.$1, size: 36),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: Ds.s4),
                  Text(s.$3, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
                ]),
              ),
            ]),
          ),
        Text(tr('Perdeu a chave e o celular? Aluno: peça ao professor para vincular de novo. Professor: fale com o suporte.'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
      ]),
    );
  }

  /// Cartão da chave de 25 caracteres: a principal (curta, sem e-mail).
  Widget _shortKeyCard() {
    final has = app.hasRecoveryKey;
    final text = app.recoveryKeyText;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Sua chave de recuperação'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          tr('Uma chave curta (25 caracteres) para levar a sua conta a outro aparelho, sem e-mail. Fica guardada de forma embaralhada no servidor. Guarde em lugar seguro: quem a tiver assume a sua conta.'),
          style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        if (has && text.isEmpty)
          Text(tr('A chave desta conta foi gerada em outro aparelho. Para ver uma aqui, gere outra (a atual deixa de valer).'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5))
        else if (has && _showShort) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.2, height: 1.5)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await _copy(text, tr('Chave'));
                  app.markRecoveryShown();
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(tr('Copiar')),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                app.markRecoveryShown();
                _upd(() => _showShort = false);
              },
              child: Text(tr('Já guardei')),
            ),
          ]),
        ] else if (has)
          FilledButton.tonalIcon(
            onPressed: () => _upd(() => _showShort = true),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(tr('Mostrar minha chave')),
          ),
        if (!has)
          SizedBox(
            width: double.infinity,
            height: Ds.primaryHeight,
            child: FilledButton.icon(
              onPressed: _keyBusy ? null : _genKey,
              icon: _keyBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.vpn_key_outlined),
              label: Text(tr('Gerar minha chave')),
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, Ds.tap), padding: EdgeInsets.zero),
              onPressed: _keyBusy ? null : _genKey,
              icon: const Icon(Icons.autorenew, size: 18),
              label: Text(tr('Gerar outra chave')),
            ),
          ),
      ]),
    );
  }

  Future<void> _doRestore() async {
    // Chave de 25 caracteres: confere no servidor. O app só mostra e explica essa chave. Quem ainda tiver guardado o texto longo da
    // versão antiga (NM1…) continua podendo colá-lo aqui: o caminho segue funcionando, só não é mais oferecido.
    final shortKey = normalizeShortKey(_restore.text);
    if (shortKey != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Entrar com esta chave?')),
          content: Text(tr('Este aparelho entra na sua conta (até 5 aparelhos). O que ficou guardado só no outro aparelho (anotações, histórico) não vem junto.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Entrar'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _upd(() => _keyBusy = true);
      var problem = await app.recoveryKeyLogin(shortKey);
      if (problem == AppState.deviceLimitProblem && mounted) {
        // A conta já está em 5 aparelhos: a pessoa escolhe qual sai.
        final drop = await pickDeviceToDrop(context, app);
        problem = drop == null ? tr('Nada mudou. Para entrar, escolha um aparelho para sair.') : await app.recoveryKeyLogin(shortKey, drop: drop);
        if (problem == AppState.deviceLimitProblem) problem = tr('Não foi possível concluir. Tente de novo.');
      }
      if (!mounted) return;
      _upd(() => _keyBusy = false);
      if (problem == null) {
        _restore.clear();
        app.say(tr('Conta recuperada neste aparelho.'));
      } else {
        app.say(problem);
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Usar outro perfil neste aparelho?')),
        content: Text(
          tr('Este aparelho passa a se identificar com o perfil da chave. O histórico que já está aqui continua, mas passa a pertencer a esse perfil. Seu código atual deixa de valer neste aparelho.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Usar este perfil')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (app.restoreProfile(_restore.text)) {
      _restore.clear();
      app.say(tr('Perfil restaurado.'));
    } else {
      app.say(
        tr('Chave inválida. Confira se copiou tudo, sem faltar nem sobrar caracteres.'),
      );
    }
  }

  /// Atualiza esta página e as subtelas abertas (elas leem o estado daqui).
  final _tick = ValueNotifier<int>(0);
  void _upd(VoidCallback fn) {
    setState(fn);
    _tick.value++;
  }

  /// 0 = QR para o meu professor, 1 = QR para os meus alunos (só com o modo professor).
  int _qrMode = 0;

  /// Abre uma subtela que se refaz quando o app ou esta página mudam.
  void _open(String title, Widget Function(BuildContext) body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: DsPageSafe(
          child: ListenableBuilder(
            listenable: Listenable.merge([app, _tick]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [body(context)],
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Toque longo no título: tela escondida de teste do Pix (só funciona para o perfil liberado no servidor).
      appBar: AppBar(title: GestureDetector(onLongPress: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanPage(app: app))), child: Text(tr('Minha conta')))),
      body: DsPageSafe(child: _mainList()),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(t, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _row(IconData icon, String title, {String? sub, Widget? trailing, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(icon, color: AppColors.textDim),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12.5)),
            trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
            onTap: onTap,
          ),
        ),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
      );

  String _dmy(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// Tela principal: uma lista curta. Cada linha abre a sua tela.
  Widget _mainList() {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.profile;
        final st = app.linkStatus;
        final linkColor = switch (st.health) {
          LinkHealth.online => AppColors.inTune,
          LinkHealth.offline || LinkHealth.serverDown => AppColors.flat,
          _ => AppColors.textDim,
        };
        final name = (p.name ?? '').trim();
        final plan = buildWeekPlan(app.myLessons, app.lessonTasksDone, DateTime.now());
        final waiting = app.awaitingTotal;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            for (final n in app.notices.where((n) => !n.seen)) ...[
              _noticeCard(context, n),
              const SizedBox(height: 12),
            ],
            AppCard(
              padding: EdgeInsets.zero,
              child: Row(children: [
                // A foto e o resto do cartão são dois controles lado a lado (nunca um dentro do outro).
                Padding(
                  padding: const EdgeInsets.only(left: Ds.s12),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () async {
                      final r = await pickPersonPhoto(context, app, hasPhoto: app.myPhoto != null);
                      if (r != null) app.setMyPhoto(r);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(Ds.s4),
                      child: Stack(clipBehavior: Clip.none, children: [
                        PersonAvatar(name: name, photo: app.myPhoto, radius: 22),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.outline)),
                            child: Icon(Icons.photo_camera_outlined, size: 13, color: AppColors.textDim),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(Ds.s8, Ds.s8, Ds.s8, Ds.s8),
                    title: Text(name.isEmpty ? tr('Defina o seu nome') : name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    subtitle: Text(tr('Código {0}', [p.shareCode])),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(tr('Meu código e QR'), (_) => _codeBody()),
                  ),
                ),
              ]),
            ),
            if (app.myPhoto != null && app.linkEnabled)
              Padding(
                padding: const EdgeInsets.only(top: Ds.s8, bottom: Ds.s8),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s4, Ds.s12, Ds.s4),
                    title: Text(tr('Mostrar a minha foto'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('Só para professores e alunos vinculados a você.'), style: Ds.support()),
                    value: app.sharePhoto,
                    onChanged: app.setSharePhoto,
                  ),
                ),
              ),
            if (app.keyPending)
              Padding(
                padding: const EdgeInsets.only(top: Ds.s8, bottom: Ds.s4),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      DsIconBadge(Icons.shield_outlined, size: 40, color: AppColors.attention),
                      const SizedBox(width: Ds.s12),
                      Expanded(child: Text(tr('Proteja sua conta'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                    ]),
                    const SizedBox(height: Ds.s8),
                    Text(app.teacherMode ? tr('Se perder este celular, seus alunos ficam sem você. Guarde a chave de recuperação.') : tr('Se perder este celular, você perde o acesso à conta. Guarde a chave de recuperação.'), style: TextStyle(color: AppColors.textDim, height: 1.35)),
                    const SizedBox(height: Ds.s12),
                    OutlinedButton.icon(
                      onPressed: () => _open(tr('Chave de recuperação'), (_) => _keyBody()),
                      icon: const Icon(Icons.key),
                      label: Text(tr('Ver a minha chave')),
                    ),
                  ]),
                ),
              ),
            _section(tr('Meus professores e aulas')),
            _row(Icons.school_outlined, tr('Professores e aulas'),
                sub: app.myTeachers.isEmpty
                    ? tr('Nenhum ainda')
                    : '${app.myTeachers.length} ${app.myTeachers.length == 1 ? tr('vinculado') : tr('vinculados')}',
                trailing: plan.open > 0 ? _pill(tr('{0} em aberto', [plan.open]), AppColors.attention) : const Icon(Icons.chevron_right),
                onTap: () => _open(tr('Professores e aulas'), _myTeacherCard)),
            _row(Icons.cloud_outlined, tr('Vínculo online'),
                sub: tr('Toque para ver, desligar ou reconectar'),
                trailing: _pill(st.title, linkColor), onTap: () => _open(tr('Vínculo online'), (_) => _linkOnlineCard())),
            _section(tr('Sou professor')),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  secondary: Icon(Icons.groups_outlined, color: AppColors.textDim),
                  title: Text(tr('Modo professor'), style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('Cadastre alunos, passe tarefas e gere relatórios.'), style: TextStyle(fontSize: 12.5)),
                  value: app.teacherMode,
                  onChanged: (v) async {
                    if (v) {
                      if (!await requireNickname(context, app, reason: tr('Para ser professor, seus alunos precisam ver o seu nome.'))) return;
                      if (!context.mounted || !await requireAdult(context, app)) return;
                      if (!context.mounted) return;
                      final connect = await askTeacherLink(context, app);
                      if (connect == null) return;
                      app.setTeacherMode(true, connect: connect);
                    } else {
                      if (!await confirmTurnOffTeacher(context, app)) return;
                      app.setTeacherMode(false);
                      if (context.mounted) await offerLinkOffAfterTeacher(context, app);
                    }
                  },
                ),
              ),
            ),
            if (app.planVisible)
              _row(Icons.workspace_premium_rounded, tr('Plano'),
                  sub: app.proActive
                      ? tr('Pro ativo até {0}', [_dmy(app.proUntil)])
                      : (app.studentLimitOn ? tr('Plano grátis · {0} de {1} alunos', [app.activeStudentCount, AppState.kFreeStudents]) : tr('Plano grátis')),
                  trailing: app.proActive ? _pill('PRO', AppColors.accent) : null,
                  onTap: () => _push(PlanPage(app: app))),
            if (app.teacherMode)
              _row(Icons.groups_rounded, tr('Meus alunos'),
                  sub: app.students.isEmpty
                      ? tr('Nenhum aluno ainda')
                      : '${app.students.length} ${app.students.length == 1 ? tr('aluno') : tr('alunos')}'
                          '${waiting > 0 ? tr(' · {0} para validar', [waiting]) : ''}',
                  onTap: () => _push(TeacherPage(app: app))),
            if (app.teacherMode)
              _row(Icons.tune_rounded, tr('Turmas, instrumentos e métodos'),
                  sub: tr('Organize o que você ensina'), onTap: _openTeachingSetup),
            _section(tr('Conta')),
            _row(Icons.badge_outlined, tr('Como funciona a sua conta'),
                sub: app.keyPending ? tr('Falta guardar a chave de recuperação') : tr('Código, chave e o que fica no celular'),
                onTap: () => showAccountExplainer(context, app,
                    onKey: () => _open(tr('Chave de recuperação'), (_) => _keyBody()), onJoin: () => _push(JoinAccountPage(app: app)))),
            _row(Icons.shield_outlined, tr('Acesso e segurança'),
                sub: app.keyPending ? tr('Você ainda não guardou a sua chave') : tr('Chave, aparelhos, e-mail e apagar dados'),
                onTap: () => _open(tr('Acesso e segurança'), _securityBody)),
            _section(tr('App')),
            _row(Icons.settings_outlined, tr('Ajustes'), onTap: () {
              app.markTab('settings');
              _push(SettingsPage(app: app));
            }),
            _row(Icons.ios_share, tr('Compartilhar o app'), onTap: () => showShareSheet(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  tr('Sem cadastro: seus dados ficam neste aparelho. A chave guarda só a sua identidade, não o histórico.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                const SizedBox(height: Ds.s4),
                Text(
                  tr('Com o vínculo online ligado, só código, apelido e tarefas das aulas vão ao servidor.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  /// Turmas, instrumentos que ensina e métodos: três atalhos numa folha só (saem do corpo da lista).
  void _openTeachingSetup() {
    showDsSheet(context, title: tr('Turmas, instrumentos e métodos'), listenable: app, children: (c) => [
          _navCard([
            DsNavRow(
                Icons.piano_outlined,
                tr('Instrumentos que ensino'),
                app.teachInstruments.isEmpty ? tr('Escolher') : app.teachInstruments.map((id) => teachingById(id)?.label ?? id).join(', '),
                () {
                  Navigator.pop(c);
                  showTeachingInstrumentsSheet(context, app);
                }),
            DsNavRow(Icons.workspaces_outline, tr('Turmas'), app.turmas.isEmpty ? tr('Separe alunos por turma ou instrumento') : app.turmas.map((t) => t.name).join(', '), () {
              Navigator.pop(c);
              _push(TurmasPage(app: app));
            }),
            DsNavRow(Icons.library_books_outlined, tr('Métodos e repertório'), tr('Monte a sua lista, um por linha'), () {
              Navigator.pop(c);
              showMaterialsSheet(context, app);
            }),
          ]),
        ]);
  }

  /// Linhas de navegação num cartão só, separadas por filete.
  Widget _navCard(List<Widget> rows) => AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Ds.radiusCard),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 64, color: AppColors.outline.withValues(alpha: 0.5)),
              rows[i],
            ],
          ]),
        ),
      );

  /// Acesso e segurança: tudo o que protege a conta e leva a ela, num lugar só, em três blocos.
  Widget _securityBody(BuildContext context) {
    final guard = <Widget>[
      if (app.emailEnabled)
        DsNavRow(Icons.alternate_email, tr('E-mail da conta'), app.emailHint.isEmpty ? tr('Recupere a conta em outro aparelho, sem senha') : app.emailHint,
            () => _open(tr('E-mail da conta'), (c) => AccountEmailBody(app: app, onSignedIn: () => Navigator.of(c).pop()))),
      if (app.linkEnabled)
        DsNavRow(Icons.devices_outlined, tr('Aparelhos'),
            app.deviceList.isEmpty ? tr('Veja onde a sua conta está aberta') : tr('{0} de {1} aparelhos', [app.deviceList.length, app.maxDevices]),
            () => _open(tr('Aparelhos'), (_) => DevicesBody(app: app))),
      if (app.cloudCopyAvail && app.teacherMode && app.linkEnabled)
        DsNavRow(Icons.cloud_outlined, tr('Cópia na nuvem'),
            app.cloudCopyOn ? tr('Ligada: suas fichas também ficam no servidor') : tr('Desligada: seus dados ficam só neste aparelho'),
            () => _open(tr('Cópia na nuvem'), (_) => CloudCopyBody(app: app))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(tr('Entrar e recuperar')),
      _navCard([
        DsNavRow(Icons.login, tr('Já tenho conta em outro aparelho'), tr('Ligue este aparelho à sua conta'), () => _push(JoinAccountPage(app: app))),
        DsNavRow(Icons.help_outline_rounded, tr('Perdi meu acesso'), tr('Passo a passo para voltar à sua conta'), () => _push(RecoveryHelpPage(app: app))),
        DsNavRow(Icons.key, tr('Chave de recuperação'), app.keyPending ? tr('Você ainda não guardou a sua chave') : tr('Guarde em lugar seguro'),
            () => _open(tr('Chave de recuperação'), (_) => _keyBody()),
            alert: app.keyPending),
      ]),
      if (guard.isNotEmpty) ...[
        _section(tr('Proteção da conta')),
        _navCard(guard),
      ],
      _section(tr('Dados e exclusão')),
      _navCard([
        DsNavRow(Icons.restart_alt_rounded, tr('Restaurar e apagar'), tr('Restaurar ajustes, apagar dados ou excluir a conta'), () => showResetSheet(context, app)),
      ]),
    ]);
  }

  /// Seu código e o QR (um só): para o seu professor ou, no modo professor, para os seus alunos.
  Widget _codeBody() {
    final p = app.profile;
    final mode = app.teacherMode ? _qrMode : 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_nameLocked)
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Seu nome'), style: Ds.support()),
                  Text(app.profile.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
              OutlinedButton.icon(
                onPressed: _askEditName,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(tr('Alterar')),
              ),
            ])
          else ...[
            TextField(
              controller: _name,
              inputFormatters: const [SafeText.name()],
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: tr('Seu nome'),
                helperText: tr('Aparece para o seu professor ou aluno quando você se vincula.'),
                helperMaxLines: 2,
              ),
            ),
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (!app.needsNickname) ...[
                    TextButton(onPressed: _cancelName, child: Text(tr('Cancelar'))),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(onPressed: _saveName, child: Text(tr('Salvar'))),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          Center(
            child: SelectableText(
              p.shareCode,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (app.teacherMode) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, label: Text(tr('Para meu professor'))),
                  ButtonSegment(value: 1, label: Text(tr('Para meus alunos'))),
                ],
                selected: {mode},
                onSelectionChanged: (v) => _upd(() => _qrMode = v.first),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                // Link, não só o código: a câmera comum do celular abre o app já com ele.
                data: mode == 0 ? '${shareLink()}/?aluno=${p.shareCode}' : '${shareLink()}/?professor=${p.shareCode}',
                size: 170,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mode == 0
                ? tr('Mostre ao seu professor: ele aponta a câmera e o Notemusic abre com o seu código. Ele só vê seus exercícios se você aceitar o convite.')
                : (app.linkEnabled
                    ? tr('Seus alunos leem este QR em Meus professores, ou digitam o código. Quem se vincular entra sozinho na sua lista.')
                    : tr('Você não está conectado: quem ler este QR só aparece na sua lista depois que você conectar.')),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          if (mode == 1 && !app.linkEnabled) ...[
            const SizedBox(height: 8),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => ensureTeacherLink(context, app, tr('Conectado, quem ler o seu QR entra sozinho na sua lista.')),
                icon: const Icon(Icons.cloud_outlined),
                label: Text(tr('Conectar')),
              ),
            ),
          ],
          if (mode == 0) ...[
            const SizedBox(height: 12),
            // O professor não está ao lado? Manda o link por mensagem: ao abrir, o cadastro dele já vem com o seu código.
            SizedBox(
              width: double.infinity,
              height: Ds.primaryHeight,
              child: FilledButton.icon(
                onPressed: () => shareStudentLink(app),
                icon: const Icon(Icons.ios_share),
                label: Text(tr('Enviar link ao professor')),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _copy(p.shareCode, tr('Código')),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(tr('Copiar código')),
            ),
          ),
        ],
      ),
    );
  }

  /// Estado do vínculo online em linguagem simples, com desligar, ligar e reconectar.
  Widget _linkOnlineCard() {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final st = app.linkStatus;
        final (icon, color) = switch (st.health) {
          LinkHealth.off => (Icons.cloud_off_outlined, AppColors.textDim),
          LinkHealth.connecting => (Icons.sync, AppColors.textDim),
          LinkHealth.online => (Icons.cloud_done_outlined, AppColors.inTune),
          LinkHealth.offline => (Icons.sync_problem, AppColors.flat),
          LinkHealth.serverDown => (Icons.cloud_off_outlined, AppColors.flat),
        };
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('Vínculo online'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                  child: Text(st.title, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(st.text, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (st.canReconnect)
                  FilledButton.icon(
                    onPressed: _reconnecting ? null : _reconnect,
                    icon: _reconnecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(tr('Reconectar agora')),
                  ),
                if (app.linkEnabled)
                  OutlinedButton.icon(
                    onPressed: _confirmOff,
                    icon: const Icon(Icons.power_settings_new, size: 18),
                    label: Text(tr('Desativar')),
                  )
                else
                  FilledButton.icon(
                    onPressed: () {
                      app.setLinkEnabled(true);
                      app.say(tr('Vínculo online ligado.'));
                    },
                    icon: const Icon(Icons.cloud_outlined, size: 18),
                    label: Text(tr('Ativar vínculo')),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(
                tr('O servidor guarda só: código, apelido, datas dos vínculos, último sinal e tarefas das aulas. Nunca áudio nem histórico.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5, height: 1.3),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _reconnecting = false;

  Future<void> _reconnect() async {
    _upd(() => _reconnecting = true);
    final msg = await app.reconnectLink();
    if (!mounted) return;
    _upd(() => _reconnecting = false);
    app.say(msg);
  }

  Future<void> _confirmOff() async {
    final ok = await confirmDisableLink(context, app);
    if (ok) {
      app.setLinkEnabled(false);
      app.say(tr('Vínculo online desligado. Você está offline.'));
    }
  }

  /// Aluno: seus professores (lidos pelo QR ou digitados). Aparece nos dois lados.
  Widget _myTeacherCard(BuildContext context) {
    final teachers = app.myTeachers;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.school_outlined, color: AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Meus professores'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            teachers.isEmpty
                ? tr('Tem professor que usa o Notemusic? Leia o QR dele (ou digite o código): você passa a aparecer na lista dele.')
                : tr('Você aparece na lista de cada professor abaixo.'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          for (final t in teachers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: app.peerPhoto(t.code) != null
                  ? PersonAvatar(name: t.name, photo: app.peerPhoto(t.code), radius: 18)
                  : Icon(t.since > 0 ? Icons.link : Icons.sync_problem, color: t.since > 0 ? AppColors.inTune : AppColors.flat),
              title: Text(t.name.isEmpty ? tr('Professor {0}', [t.code]) : t.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.paused
                  ? tr('Código {0} · aulas pausadas pelo professor', [t.code])
                  : (t.since > 0 ? tr('Código {0} · vinculado', [t.code]) : tr('Código {0} · a vincular quando houver conexão', [t.code]))),
              trailing: IconButton(
                tooltip: tr('Encerrar vínculo'),
                icon: const Icon(Icons.link_off),
                onPressed: () => _confirmRemoveTeacher(context, t),
              ),
            ),
          if (app.shareStudy && teachers.length > 1)
            for (final t in teachers)
              SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 8),
                dense: true,
                title: Text(tr('{0} vê o meu estudo', [t.name.isEmpty ? t.code : t.name])),
                value: app.studySeenBy(t.code),
                onChanged: (v) => app.setStudySeenBy(t.code, v),
              ),
          if (app.hasTeacherSide) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _push(MyLessonsPage(app: app)),
              icon: const Icon(Icons.checklist_rtl),
              label: Text(tr('Ver minhas aulas')),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () async {
              final s = await scanShareCode(
                context,
                title: tr('Vincular com professor'),
                want: 'professor',
                check: app.checkTeacherCode,
                onCamera: app.setCameraStatus,
              );
              if (s != null) _registerTeacher(s.code);
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(teachers.isEmpty ? tr('Ler QR ou digitar código') : tr('Adicionar outro professor')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveTeacher(BuildContext context, LinkedPerson t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Encerrar o vínculo?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('As aulas com {0} ficam guardadas aqui, só para ler.', [t.name.isEmpty ? tr('este professor') : t.name])),
          const SizedBox(height: 8),
          Text(tr('As tarefas em aberto saem da sua lista e ele deixa de ver o seu estudo.')),
          const SizedBox(height: 8),
          Text(tr('Ele continua com o histórico. Para voltar, leia o QR dele de novo.')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Encerrar'))),
        ],
      ),
    );
    if (ok == true) app.removeMyTeacher(t.code);
  }

  Future<void> _registerTeacher(String code) async {
    if (!await requireNickname(context, app, reason: tr('Para vincular a um professor, ele precisa saber quem você é.'))) return;
    if (!mounted || !await confirmStudentLink(context, app)) return;
    final err = await app.addMyTeacher(code);
    if (err != null) app.say(err);
  }

  /// Aviso para o aluno: "Fulano adicionou você" ou "nova aula". Fica até ser dispensado.
  Widget _noticeCard(BuildContext context, AppNotice n) {
    return Material(
      color: AppColors.info.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(n.kind == 'lesson' ? Icons.assignment_turned_in_outlined : (n.kind == 'support' ? Icons.support_agent : Icons.how_to_reg_outlined),
                  color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(child: Text(n.text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3))),
              IconButton(
                tooltip: tr('Dispensar'),
                visualDensity: VisualDensity.compact,
                onPressed: () => app.dismissNotice(n),
                icon: const Icon(Icons.close, size: 20),
              ),
            ]),
            if (n.kind != 'support')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  app.dismissNotice(n);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => MyLessonsPage(app: app)),
                  );
                },
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(tr('Ver minhas aulas')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chave de recuperação e "usar um perfil que já tenho".
  Widget _keyBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _howKeyCard(),
        const SizedBox(height: 16),
        _shortKeyCard(),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Usar uma chave que já tenho'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(tr('Digite a chave de 25 caracteres.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _restore,
                inputFormatters: const [SafeText.paste(600)],
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(hintText: 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'),
                onChanged: (_) => _upd(() {}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _restore.text.trim().isEmpty || _keyBusy ? null : _doRestore,
                icon: const Icon(Icons.restore),
                label: Text(tr('Entrar com a chave')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Tenho um código de suporte'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                tr('Perdeu a chave? Digite o código do perfil e o de suporte (24 h, uso único). O aparelho antigo perde o acesso.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _claimCode,
                inputFormatters: [...codeFormatters, LengthLimitingTextInputFormatter(9)],
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr('Código do seu perfil'), hintText: 'K7QM-4TXD'),
                onChanged: (_) => _upd(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _claimSupport,
                inputFormatters: [...codeFormatters, LengthLimitingTextInputFormatter(9)],
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr('Código de suporte'), hintText: 'XXXX-XXXX'),
                onChanged: (_) => _upd(() {}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _claiming || _claimCode.text.trim().isEmpty || _claimSupport.text.trim().isEmpty ? null : _doClaim,
                icon: _claiming
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.support_agent),
                label: Text(tr('Liberar neste aparelho')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _doClaim() async {
    _upd(() => _claiming = true);
    final err = await app.claimWithSupport(_claimCode.text, _claimSupport.text);
    if (!mounted) return;
    _upd(() => _claiming = false);
    if (err == null) {
      _claimCode.clear();
      _claimSupport.clear();
      app.say(tr('Conta liberada neste aparelho.'));
    } else {
      app.say(err);
    }
  }
}

/// Chamado ao abrir o app por um link/QR de professor (`?professor=K7QM-4TXD`):
/// pergunta se é o professor do usuário e registra.
Future<void> handleIncomingTeacherCode(BuildContext context, AppState app) async {
  final code = app.incomingTeacherCode;
  if (code == null) return;
  app.incomingTeacherCode = null;
  if (app.teacherCodes.contains(code)) {
    app.say(tr('Este professor já está na sua lista.'));
    return;
  }
  final problem = app.checkTeacherCode(code);
  if (problem != null) {
    app.say(problem);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Código de professor')),
      content: Text(tr('O código {0} foi lido. Vincular como o seu professor? Ele passa a aparecer na sua lista e você na lista dele. O servidor guarda os códigos, o apelido e a data do vínculo, e as tarefas das aulas que ele encerrar para você; nada dos seus exercícios.', [code])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
        FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.link, size: 18), label: Text(tr('Vincular'))),
      ],
    ),
  );
  if (ok == true) {
    if (!context.mounted || !await requireNickname(context, app, reason: tr('Para vincular a um professor, ele precisa saber quem você é.'))) return;
    if (!context.mounted || !await confirmStudentLink(context, app)) return;
    final err = await app.addMyTeacher(code);
    if (err != null) app.say(err);
  }
}
