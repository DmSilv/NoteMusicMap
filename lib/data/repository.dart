import 'dart:convert';
import 'dart:math';

import 'package:afina_core/afina_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onde ficam os dados que pertencem ao PERFIL (e que um dia serão sincronizados):
/// o próprio perfil, o histórico de sessões e os alunos do professor.
///
/// A interface não sabe se os dados estão no aparelho ou na nuvem. Hoje só existe
/// [LocalRepository]; na Fase 2 entra um repositório remoto que usa o mesmo
/// contrato, e a interface do app não precisa mudar. Ajustes do aparelho
/// (tema, afinação, PIN…) NÃO passam por aqui: são do aparelho, não do perfil.
abstract class Repository {
  /// Perfil guardado, ou um novo (criado e salvo na hora) no primeiro uso.
  Future<Profile> loadOrCreateProfile();
  Future<void> saveProfile(Profile p);

  /// Sessões do próprio usuário, mais recente primeiro.
  Future<List<SessionRecord>> loadSessions();
  Future<void> saveSessions(List<SessionRecord> sessions);

  /// Alunos do professor (cada um com tarefas, notas e sessões).
  Future<List<Student>> loadStudents();
  Future<void> saveStudents(List<Student> students);
}

/// Guarda tudo no aparelho (SharedPreferences). Funciona sem rede.
class LocalRepository implements Repository {
  static const profileKey = 'profile';
  static const sessionsKey = 'sessions2';
  static const studentsKey = 'students';

  final SharedPreferences _p;
  final Random _rnd;
  LocalRepository(this._p, {Random? random}) : _rnd = random ?? Random.secure();

  @override
  Future<Profile> loadOrCreateProfile() async {
    final raw = _p.getString(profileKey);
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          final p = Profile.tryFrom(j.cast<String, dynamic>());
          if (p != null) return p;
        }
      } catch (_) {}
    }
    // Primeiro uso (ou dado ilegível). Quem já usava o modo professor antes de
    // existir perfil mantém o modo ligado: nada muda para essa pessoa.
    final p = Profile.create(_rnd)..teacher = _p.getBool('teacherMode') ?? false;
    await saveProfile(p);
    return p;
  }

  @override
  Future<void> saveProfile(Profile p) async {
    await _p.setString(profileKey, jsonEncode(p.toJson()));
  }

  @override
  Future<List<SessionRecord>> loadSessions() async {
    final raw = _p.getString(sessionsKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in (jsonDecode(raw) as List)) ?SessionRecord.tryFromJson((j as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveSessions(List<SessionRecord> sessions) async {
    await _p.setString(sessionsKey, jsonEncode([for (final r in sessions) r.toJson()]));
  }

  @override
  Future<List<Student>> loadStudents() async {
    final raw = _p.getString(studentsKey);
    if (raw == null) return [];
    try {
      return [for (final x in (jsonDecode(raw) as List)) ?Student.tryFrom((x as Map).cast<String, dynamic>())];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveStudents(List<Student> students) async {
    await _p.setString(studentsKey, jsonEncode([for (final s in students) s.toJson()]));
  }
}
