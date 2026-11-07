import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
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
  void dispose() {
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
        ],
      ),
    );
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
                        data: 'notemusic:${p.shareCode}',
                        size: 150,
                        padding: EdgeInsets.zero,
                      ),
                    ),
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
