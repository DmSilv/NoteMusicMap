import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import 'safe_input.dart';
import '../link/link_service.dart' show LinkedPerson;
import 'qr_scan_page.dart';
import 'share_sheet.dart' show shareLink;
import 'teacher_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Meu perfil": o código que identifica você (sem cadastro) e a chave de
/// recuperação, que permite levar o histórico para outro aparelho.
class ProfilePage extends StatefulWidget {
  final AppState app;

  /// 0 = Meu perfil, 1 = Professor.
  final int initialTab;
  const ProfilePage({super.key, required this.app, this.initialTab = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _showKey = false;
  final _restore = TextEditingController();
  late final TextEditingController _name = TextEditingController(
    text: widget.app.profile.name ?? '',
  );

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.watchLinks(); // atualiza os vínculos enquanto esta tela está aberta
  }

  @override
  void dispose() {
    app.unwatchLinks();
    _restore.dispose();
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
      setState(() => _showKey = false);
      app.say('Perfil restaurado.');
    } else {
      app.say(
        'Chave inválida. Confira se copiou tudo, sem faltar nem sobrar caracteres.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Perfil e professor'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.badge_outlined), text: 'Meu perfil'),
              Tab(icon: Icon(Icons.school_outlined), text: 'Professor'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(children: [_profileTab(), _teacherTab()]),
        ),
      ),
    );
  }

  /// Aba "Professor": liga/desliga a capacidade e leva à área do professor.
  Widget _teacherTab() {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Modo professor',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Todos começam como aluno e usam o app inteiro. Ligue se quiser cadastrar alunos, '
                    'passar tarefas, anotar observações e gerar relatórios. Os dados ficam neste aparelho.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  value: app.teacherMode,
                  onChanged: app.setTeacherMode,
                ),
                if (app.teacherMode) ...[
                  const SizedBox(height: 6),
                  Text(
                    app.students.isEmpty
                        ? 'Nenhum aluno cadastrado ainda.'
                        : '${app.students.length} aluno${app.students.length > 1 ? 's' : ''} cadastrado${app.students.length > 1 ? 's' : ''}.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TeacherPage(app: app),
                      ),
                    ),
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('Abrir a área do professor'),
                  ),
                ],
              ],
            ),
          ),
          if (app.teacherMode) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seu QR de professor',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seus alunos leem este QR em Meu perfil › Meus professores. Eles também podem digitar o código. '
                    'Quem se vincular aparece sozinho na sua lista de alunos.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  if (!app.linkEnabled) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => app.setLinkEnabled(true),
                      icon: const Icon(Icons.cloud_outlined),
                      label: const Text('Ligar o vínculo online'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: SelectableText(
                      app.profile.shareCode,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: QrImageView(
                        data: '${shareLink()}/?professor=${app.profile.shareCode}',
                        size: 150,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Liga e desliga o vínculo online e mostra se está conectado.
  Widget _linkOnlineCard() {
    final on = app.linkEnabled;
    final (icon, color, status) = !on
        ? (Icons.cloud_off_outlined, AppColors.textDim, 'Desligado')
        : app.linkUnavailable
            ? (Icons.cloud_off_outlined, AppColors.flat, 'Ainda não disponível no servidor')
            : app.linkOnline == false
                ? (Icons.sync_problem, AppColors.flat, 'Sem conexão agora')
                : app.linkOnline == true
                    ? (Icons.cloud_done_outlined, AppColors.inTune, 'Conectado')
                    : (Icons.sync, AppColors.textDim, 'Conectando…');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(icon, color: color),
            title: const Text('Vínculo online', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              'Quando um professor ler o seu QR (ou você ler o dele), o vínculo aparece nos dois aparelhos em '
              'poucos segundos. O servidor guarda só os códigos, o apelido e a data do vínculo.',
              style: const TextStyle(fontSize: 12.5),
            ),
            value: on,
            onChanged: app.setLinkEnabled,
          ),
          Text(status, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
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
    final err = await app.addMyTeacher(code);
    if (err != null) app.say(err);
  }

  Widget _profileTab() {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.profile;
        final key = recoveryKeyFor(p);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seu código',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sem cadastro: o app criou este código para você. Um professor pode usá-lo para '
                    'encontrar você, mas só consegue ver seus exercícios se você aceitar o convite dele.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        // Link, não só o código: a câmera comum do celular do professor abre o app já com ele.
                        data: '${shareLink()}/?aluno=${p.shareCode}',
                        size: 150,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mostre este QR ao seu professor: ele aponta a câmera do celular e o Notemusic '
                    'abre já com o seu código.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _copy(p.shareCode, 'Código'),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar código'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    inputFormatters: const [SafeText.name()],
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Seu nome (opcional)',
                      helperText: 'Só para você se reconhecer. Não é enviado a ninguém.',
                    ),
                    onChanged: app.setProfileName,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _linkOnlineCard(),
            const SizedBox(height: 12),
            _myTeacherCard(context),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: AppColors.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chave de recuperação',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Guarde esta chave em lugar seguro (gerenciador de senhas ou anotação privada). '
                    'Com ela você leva seu perfil para outro aparelho ou depois de reinstalar o app. '
                    'Quem tiver a chave pode se passar por você: não envie a ninguém.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  if (p.recoveryShownAt == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Você ainda não guardou a sua chave.',
                      style: TextStyle(
                        color: AppColors.sharp,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (!_showKey)
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _showKey = true),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Mostrar minha chave'),
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        key,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
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
                            setState(() => _showKey = false);
                          },
                          child: const Text('Já guardei'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Usar um perfil que já tenho',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cole a chave de recuperação do outro aparelho.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _restore,
                    inputFormatters: const [SafeText.paste(600)],
                    minLines: 2,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(hintText: 'NM1-…'),
                    onChanged: (_) => setState(() {}),
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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Hoje seus dados ficam só neste aparelho. A chave guarda a sua identidade, não o histórico: '
                'o envio do histórico entre aparelhos virá numa próxima etapa.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
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
          'Ele passa a aparecer na sua lista e você na lista dele. O servidor guarda só os códigos, '
          'o apelido e a data do vínculo; nada dos seus exercícios.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vincular')),
      ],
    ),
  );
  if (ok == true) {
    final err = await app.addMyTeacher(code);
    if (err != null) app.say(err);
  }
}
