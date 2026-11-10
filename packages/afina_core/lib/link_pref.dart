/// Regra do "Vínculo online": ligado por padrão para quem tem professor, aluno ou
/// modo professor, e só desligado se a pessoa escolheu desligar (e confirmou o aviso).
library;

/// Decide se o vínculo online deve estar ligado ao abrir o app.
///
/// - [pref] é a escolha explícita guardada ("on" ou "off"); null = nunca escolheu.
/// - [legacyOn] é o valor antigo (versões que ligavam só ao vincular alguém).
/// - Sem escolha explícita, liga sozinho quando há alguém para receber avisos
///   (modo professor, professor vinculado ou aluno cadastrado com código).
bool linkShouldBeOn({
  String? pref,
  required bool legacyOn,
  required bool teacherMode,
  required bool hasTeachers,
  required bool hasStudentsWithCode,
}) {
  if (pref == 'off') return false;
  if (pref == 'on') return true;
  if (legacyOn) return true;
  return teacherMode || hasTeachers || hasStudentsWithCode;
}

/// O vínculo está desligado mesmo havendo gente que depende dele? (para avisar a pessoa)
bool linkNeedsAttention({
  required bool enabled,
  required bool teacherMode,
  required bool hasTeachers,
  required bool hasStudentsWithCode,
}) =>
    !enabled && (teacherMode || hasTeachers || hasStudentsWithCode);
