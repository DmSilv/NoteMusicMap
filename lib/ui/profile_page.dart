import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import 'my_lessons_page.dart';
import 'safe_input.dart';
import '../link/link_service.dart' show LinkedPerson;
import 'qr_scan_page.dart';
import 'settings_page.dart' show SettingsPage;
import 'share_sheet.dart' show shareLink, showShareSheet;
import 'teacher_page.dart';
import 'hello_bar.dart';
import 'link_bar.dart';
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
  bool _showKey = false;
  bool _fast = false;
  final _restore = TextEditingController();
  final _claimCode = TextEditingController();
  final _claimSupport = TextEditingController();
  bool _claiming = false;
  late final TextEditingController _name = TextEditingController(
    text: widget.app.profile.name ?? '',
  );

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    // Atualiza os vínculos enquanto esta tela está aberta. Quem ainda não tem professor consulta
    // mais depressa (10 s): é quem espera um professor adicioná-lo.
    _fast = app.myTeachers.isEmpty;
    app.watchLinks(fast: _fast);
    app.markTab('profile');
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
    app.say('$what copiado.');
  }

  Future<void> _doRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Usar outro perfil neste aparelho?'),
        content: const Text(
          'Este aparelho passa a se identificar com o perfil da chave. O histórico que já está aqui '
          'continua, mas passa a pertencer a esse perfil. Seu código atual deixa de valer neste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Usar este perfil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (app.restoreProfile(_restore.text)) {
      _restore.clear();
      _upd(() => _showKey = false);
      app.say('Perfil restaurado.');
    } else {
      app.say(
        'Chave inválida. Confira se copiou tudo, sem faltar nem sobrar caracteres.',
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
        body: SafeArea(
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
      appBar: AppBar(title: const Text('Minha conta')),
      body: SafeArea(child: _mainList()),
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
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                leading: CircleAvatar(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                ),
                title: Text(name.isEmpty ? 'Defina o seu nome' : name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                subtitle: Text('Código ${p.shareCode}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open('Meu código e QR', (_) => _codeBody()),
              ),
            ),
            _section('Vínculos'),
            _row(Icons.cloud_outlined, 'Vínculo online',
                trailing: _pill(st.title, linkColor), onTap: () => _open('Vínculo online', (_) => _linkOnlineCard())),
            _row(Icons.school_outlined, 'Meus professores',
                sub: app.myTeachers.isEmpty
                    ? 'Nenhum ainda'
                    : '${app.myTeachers.length} ${app.myTeachers.length == 1 ? 'vinculado' : 'vinculados'}',
                onTap: () => _open('Meus professores', _myTeacherCard)),
            if (app.hasTeacherSide)
              _row(Icons.checklist_rtl, 'Minhas aulas',
                  trailing: plan.open > 0 ? _pill('${plan.open} em aberto', AppColors.accent) : const Icon(Icons.chevron_right),
                  onTap: () => _push(MyLessonsPage(app: app))),
            _section('Professor'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  secondary: Icon(Icons.groups_outlined, color: AppColors.textDim),
                  title: const Text('Modo professor', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Cadastre alunos, passe tarefas e gere relatórios.', style: TextStyle(fontSize: 12.5)),
                  value: app.teacherMode,
                  onChanged: (v) async {
                    if (v && !await requireNickname(context, app, reason: 'Para ser professor, seus alunos precisam ver o seu nome.')) return;
                    app.setTeacherMode(v);
                  },
                ),
              ),
            ),
            if (app.teacherMode)
              _row(Icons.groups_rounded, 'Meus alunos',
                  sub: app.students.isEmpty
                      ? 'Nenhum aluno ainda'
                      : '${app.students.length} ${app.students.length == 1 ? 'aluno' : 'alunos'}'
                          '${waiting > 0 ? ' · $waiting para validar' : ''}',
                  onTap: () => _push(TeacherPage(app: app))),
            _section('Conta'),
            _row(Icons.key, 'Chave de recuperação',
                sub: p.recoveryShownAt == null ? 'Você ainda não guardou a sua chave' : null,
                onTap: () => _open('Chave de recuperação', (_) => _keyBody())),
            _row(Icons.settings_outlined, 'Ajustes', onTap: () {
              app.markTab('settings');
              _push(SettingsPage(app: app));
            }),
            _row(Icons.ios_share, 'Compartilhar o app', onTap: () => showShareSheet(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                'Sem cadastro: seus dados ficam neste aparelho. A chave guarda só a sua identidade, não o histórico.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Seu código e o QR (um só): para o seu professor ou, no modo professor, para os seus alunos.
  Widget _codeBody() {
    final p = app.profile;
    final mode = app.teacherMode ? _qrMode : 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            inputFormatters: const [SafeText.name()],
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Seu nome',
              helperText: 'Aparece para o seu professor ou aluno quando você se vincula.',
              helperMaxLines: 2,
            ),
            onChanged: app.setProfileName,
          ),
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
                segments: const [
                  ButtonSegment(value: 0, label: Text('Para meu professor')),
                  ButtonSegment(value: 1, label: Text('Para meus alunos')),
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
                ? 'Mostre ao seu professor: ele aponta a câmera e o Notemusic abre com o seu código. '
                    'Ele só vê seus exercícios se você aceitar o convite.'
                : 'Seus alunos leem este QR em Meus professores, ou digitam o código. Quem se vincular entra sozinho na sua lista.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          if (mode == 1 && !app.linkEnabled) ...[
            const SizedBox(height: 8),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => app.setLinkEnabled(true),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Ligar o vínculo online'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _copy(p.shareCode, 'Código'),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar código'),
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
                const Expanded(child: Text('Vínculo online', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
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
                    label: const Text('Reconectar agora'),
                  ),
                if (app.linkEnabled)
                  OutlinedButton.icon(
                    onPressed: _confirmOff,
                    icon: const Icon(Icons.power_settings_new, size: 18),
                    label: const Text('Desativar'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () {
                      app.setLinkEnabled(true);
                      app.say('Vínculo online ligado.');
                    },
                    icon: const Icon(Icons.cloud_outlined, size: 18),
                    label: const Text('Ativar vínculo'),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(
                'O servidor guarda só: código, apelido, datas dos vínculos, último sinal e tarefas das aulas. Nunca áudio nem histórico.',
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
      app.say('Vínculo online desligado. Você está offline.');
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
            Icon(Icons.school_outlined, color: AppColors.accent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Meus professores', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            teachers.isEmpty
                ? 'Tem professor que usa o Notemusic? Leia o QR dele (ou digite o código): você passa a aparecer na lista dele.'
                : 'Você aparece na lista de cada professor abaixo.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          for (final t in teachers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(t.since > 0 ? Icons.link : Icons.sync_problem,
                  color: t.since > 0 ? AppColors.inTune : AppColors.flat),
              title: Text(t.name.isEmpty ? 'Professor ${t.code}' : t.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.since > 0 ? 'Código ${t.code} · vinculado' : 'Código ${t.code} · a vincular quando houver conexão'),
              trailing: IconButton(
                tooltip: 'Encerrar vínculo',
                icon: const Icon(Icons.link_off),
                onPressed: () => _confirmRemoveTeacher(context, t),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () async {
              final s = await scanShareCode(
                context,
                title: 'Ler QR do professor',
                want: 'professor',
                check: app.checkTeacherCode,
                onCamera: app.setCameraStatus,
              );
              if (s != null) _registerTeacher(s.code);
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(teachers.isEmpty ? 'Ler QR do professor' : 'Adicionar outro professor'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveTeacher(BuildContext context, LinkedPerson t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Encerrar o vínculo?'),
        content: Text('Você sai da lista de ${t.name.isEmpty ? 'este professor' : t.name} e ele sai da sua. '
            'Para vincular de novo, leia o QR outra vez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok == true) app.removeMyTeacher(t.code);
  }

  Future<void> _registerTeacher(String code) async {
    if (!await requireNickname(context, app, reason: 'Para vincular a um professor, ele precisa saber quem você é.')) return;
    final err = await app.addMyTeacher(code);
    if (err != null) app.say(err);
  }

  /// Aviso para o aluno: "Fulano adicionou você" ou "nova aula". Fica até ser dispensado.
  Widget _noticeCard(BuildContext context, AppNotice n) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(n.kind == 'lesson' ? Icons.assignment_turned_in_outlined : (n.kind == 'support' ? Icons.support_agent : Icons.how_to_reg_outlined),
                  color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(n.text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3))),
              IconButton(
                tooltip: 'Dispensar',
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
                label: const Text('Ver minhas aulas'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chave de recuperação e "usar um perfil que já tenho".
  Widget _keyBody() {
    final p = app.profile;
    final key = recoveryKeyFor(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guarde em lugar seguro: com ela você leva o perfil a outro aparelho. Quem a tiver pode se passar por você.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              if (p.recoveryShownAt == null) ...[
                const SizedBox(height: 8),
                Text('Você ainda não guardou a sua chave.',
                    style: TextStyle(color: AppColors.sharp, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
              const SizedBox(height: 10),
              if (!_showKey)
                FilledButton.tonalIcon(
                  onPressed: () => _upd(() => _showKey = true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Mostrar minha chave'),
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                  child: SelectableText(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await _copy(key, 'Chave');
                        app.markRecoveryShown();
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      app.markRecoveryShown();
                      _upd(() => _showKey = false);
                    },
                    child: const Text('Já guardei'),
                  ),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Usar um perfil que já tenho', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Cole a chave de recuperação do outro aparelho.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _restore,
                inputFormatters: const [SafeText.paste(600)],
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: 'NM1-…'),
                onChanged: (_) => _upd(() {}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _restore.text.trim().isEmpty ? null : _doRestore,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar perfil'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tenho um código de suporte', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Perdeu a chave? Digite o código do perfil e o de suporte (24 h, uso único). O aparelho antigo perde o acesso.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _claimCode,
                inputFormatters: [...codeFormatters, LengthLimitingTextInputFormatter(9)],
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Código do seu perfil', hintText: 'K7QM-4TXD'),
                onChanged: (_) => _upd(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _claimSupport,
                inputFormatters: [...codeFormatters, LengthLimitingTextInputFormatter(9)],
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Código de suporte', hintText: 'XXXX-XXXX'),
                onChanged: (_) => _upd(() {}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _claiming || _claimCode.text.trim().isEmpty || _claimSupport.text.trim().isEmpty ? null : _doClaim,
                icon: _claiming
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.support_agent),
                label: const Text('Liberar neste aparelho'),
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
      app.say('Conta liberada neste aparelho.');
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
    app.say('Este professor já está na sua lista.');
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
      title: const Text('Código de professor'),
      content: Text('O código $code foi lido. Vincular como o seu professor? '
          'Ele passa a aparecer na sua lista e você na lista dele. O servidor guarda os códigos, '
          'o apelido e a data do vínculo, e as tarefas das aulas que ele encerrar para você; nada dos seus exercícios.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
        FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.link, size: 18), label: const Text('Vincular')),
      ],
    ),
  );
  if (ok == true) {
    if (!context.mounted || !await requireNickname(context, app, reason: 'Para vincular a um professor, ele precisa saber quem você é.')) return;
    final err = await app.addMyTeacher(code);
    if (err != null) app.say(err);
  }
}
