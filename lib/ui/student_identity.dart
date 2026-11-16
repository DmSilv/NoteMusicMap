import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'theme.dart';

/// Selo do vínculo online do aluno.
Widget linkBadge(Student s) {
  final (icon, color, text) = switch (s.linkState) {
    'active' => (Icons.link, AppColors.inTune, tr('Vinculado')),
    'pending' => (Icons.sync_problem, AppColors.flat, tr('A vincular')),
    'ended' => (Icons.link_off, AppColors.sharp, tr('Encerrado pelo aluno')),
    _ => (Icons.phone_android, AppColors.textDim, tr('Só neste aparelho')),
  };
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 3),
    Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
  ]);
}

/// Cor própria do aluno (sempre a mesma para o mesmo aluno), para distinguir de relance quem tem nome igual.
/// Sai do id, entre 8 tons que combinam com o tema.
Color studentTint(Student s) {
  const hues = [168.0, 200.0, 262.0, 320.0, 24.0, 48.0, 100.0, 350.0];
  var h = 0;
  for (final c in s.id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, hues[h % hues.length], 0.62, AppColors.dark ? 0.62 : 0.34).toColor();
}

/// O nome que o próprio aluno registrou no perfil dele, se for diferente do que o professor usa.
String? remoteNameOf(Student s) {
  final r = (s.remoteName ?? '').trim();
  if (r.isEmpty || r == s.name.trim() || isDefaultStudentName(r, s.code ?? '')) return null;
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
        backgroundColor: studentTint(s).withValues(alpha: 0.22),
        child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
            style: TextStyle(
                color: studentTint(s), fontWeight: FontWeight.w800, fontSize: large ? 20 : 16)),
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
                child: Text(tr('Código {0}', [s.code]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5, letterSpacing: 0.5)),
              ),
              InkResponse(
                radius: 16,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: s.code!));
                  app.say(tr('Código copiado.'));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(Icons.copy, size: 14, color: AppColors.textDim),
                ),
              ),
            ])
          else
            Text(tr('Sem código ainda'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          if (remote != null)
            Text(tr('Nome no perfil dele: {0}', [remote]),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          const SizedBox(height: 2),
          linkBadge(s),
        ]),
      ),
    ]);
  }
}
