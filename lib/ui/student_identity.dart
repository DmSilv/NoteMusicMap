import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'theme.dart';

/// Selo do vínculo online do aluno.
Widget linkBadge(Student s) {
  final (icon, color, text) = switch (s.linkState) {
    'active' => (Icons.link, AppColors.inTune, 'Vinculado'),
    'pending' => (Icons.sync_problem, AppColors.flat, 'A vincular'),
    'ended' => (Icons.link_off, AppColors.sharp, 'Encerrado pelo aluno'),
    _ => (Icons.phone_android, AppColors.textDim, 'Só neste aparelho'),
  };
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 3),
    Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
  ]);
}

/// O nome que o próprio aluno registrou no perfil dele, se for diferente do que o professor usa.
String? remoteNameOf(Student s) {
  final r = (s.remoteName ?? '').trim();
  if (r.isEmpty || r == s.name.trim() || r == 'Aluno ${s.code}') return null;
  return r;
}

/// Quem é o aluno: o NOME e o CÓDIGO juntos (e o nome que o próprio aluno registrou, se for
/// diferente do que o professor usa), mais o estado do vínculo. Serve de cabeçalho em qualquer
/// tela que mexe com o aluno, para o professor nunca ficar só com o código.
class StudentIdentity extends StatelessWidget {
  final AppState app;
  final Student student;

  /// Maior (cabeçalho da ficha) ou compacto (dentro de formulários).
  final bool large;
  const StudentIdentity({super.key, required this.app, required this.student, this.large = false});

  @override
  Widget build(BuildContext context) {
    final s = student;
    final remote = remoteNameOf(s);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(
        radius: large ? 24 : 18,
        backgroundColor: AppColors.accent.withValues(alpha: 0.2),
        child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
            style: TextStyle(
                color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: large ? 20 : 16)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: large ? 19 : 16)),
          if (s.code != null)
            Row(children: [
              Flexible(
                child: Text('Código ${s.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5, letterSpacing: 0.5)),
              ),
              InkResponse(
                radius: 16,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: s.code!));
                  app.say('Código copiado.');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(Icons.copy, size: 14, color: AppColors.textDim),
                ),
              ),
            ])
          else
            Text('Sem código ainda', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          if (remote != null)
            Text('Nome no perfil dele: $remote',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          const SizedBox(height: 2),
          linkBadge(s),
        ]),
      ),
    ]);
  }
}
