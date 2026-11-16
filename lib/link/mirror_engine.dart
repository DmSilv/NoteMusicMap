import 'dart:async';
import 'dart:convert';

import 'package:afina_core/afina_core.dart';

import 'link_service.dart';

/// Onde o motor guarda o que já foi trocado (um texto por nome).
abstract class MirrorMemory {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// Motor do espelho da conta entre aparelhos (ver api/_lib/mirror.js e packages/afina_core/lib/mirror.dart).
/// Só trabalha quando o servidor diz que a conta tem 2 ou mais aparelhos. A cada rodada: lista o que o servidor tem
/// (barato), decide o que enviar, baixar ou juntar ([planMirror]) e faz. Quem muda o conteúdo é o [apply] do app.
class MirrorEngine {
  MirrorEngine({
    required this.links,
    required this.account,
    required this.memory,
    required this.build,
    required this.apply,
    required this.deleteLocal,
    required this.changed,
    this.onNote,
    this.onError,
  }) {
    _loadMeta();
  }

  final LinkService links;

  /// (código do perfil, segredo do aparelho): lidos na hora, porque o perfil pode mudar.
  final (String, String) Function() account;
  /// Onde guardar o que já foi trocado (no app, as preferências do aparelho).
  final MirrorMemory? Function() memory;

  /// As seções deste aparelho agora.
  final Map<String, LocalSection> Function() build;

  /// Aplica uma seção que veio do servidor. [merge] = junta com o que há aqui (os dois lados mudaram).
  final void Function(String sec, String data, {required bool merge}) apply;
  final void Function(String sec) deleteLocal;

  /// O conteúdo mudou por causa do espelho (a tela deve se redesenhar).
  final void Function() changed;
  final void Function(String text)? onNote;

  /// Erro inesperado numa rodada (para registro e testes).
  final void Function(Object error, StackTrace stack)? onError;

  /// A conta está em 2+ aparelhos (o servidor disse na última consulta barata).
  bool on = false;

  /// Revisão do espelho que este aparelho viu por último.
  int rev = 0;

  /// Enquanto o espelho aplica algo no app, as gravações que isso provoca não disparam outra rodada.
  bool applying = false;

  final Map<String, MirrorMeta> meta = {};
  Timer? _timer;
  bool _busy = false;
  bool _again = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _loadMeta() {
    try {
      final raw = memory()?.read('mirror_meta');
      if (raw == null || raw.isEmpty) return;
      for (final e in (jsonDecode(raw) as Map).entries) {
        final v = (e.value as List);
        meta[e.key as String] = MirrorMeta(v[0] as String, (v[1] as num).toInt());
      }
      rev = int.tryParse(memory()?.read('mirror_rev') ?? '') ?? 0;
    } catch (_) {
      meta.clear();
    }
  }

  void _saveMeta() {
    memory()?.write('mirror_meta', jsonEncode({for (final e in meta.entries) e.key: [e.value.hash, e.value.u]}));
    memory()?.write('mirror_rev', '$rev');
  }

  /// Esquece tudo (outra conta foi assumida neste aparelho).
  void reset() {
    on = false;
    rev = 0;
    meta.clear();
    _timer?.cancel();
    memory()?.remove('mirror_meta');
    memory()?.remove('mirror_rev');
  }

  /// Olha a consulta barata ou a sincronização: liga/desliga o espelho e vê se o outro aparelho mudou algo.
  void note(LinkReply r) {
    if (!r.ok) return;
    if (r.mirrorOn) {
      final wasOff = !on;
      on = true;
      if (wasOff || r.mirrorRev != rev) schedule(const Duration(milliseconds: 300));
    } else if (on) {
      // A conta voltou a ter um aparelho só: o espelho foi apagado no servidor.
      on = false;
      meta.clear();
      _saveMeta();
    }
  }

  /// Alguma coisa mudou neste aparelho: manda daqui a pouco (junta várias mudanças seguidas).
  void kick() {
    if (!on || applying) return;
    schedule(const Duration(seconds: 4));
  }

  void schedule(Duration d) {
    _timer?.cancel();
    final wait = _last.add(const Duration(seconds: 8)).difference(DateTime.now());
    _timer = Timer(wait > d ? wait : d, () => unawaited(round()));
  }

  Future<void> round() async {
    if (!on) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      await _round();
    } catch (e, st) {
      onError?.call(e, st); // tenta de novo na próxima mudança
    } finally {
      _busy = false;
      _last = DateTime.now();
      if (_again) {
        _again = false;
        schedule(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _round() async {
    final (code, secret) = account();
    final list = await links.miList(code, secret);
    if (list.mirrorOff) {
      on = false;
      return;
    }
    if (!list.ok) return; // sem internet: fica para depois
    final remote = list.secs;
    final local = build();
    final ops = planMirror(local: local, meta: meta, remote: remote);
    if (ops.isEmpty) {
      rev = list.mirrorRev;
      _saveMeta();
      return;
    }

    // Segurança: se quase tudo parece "apagado aqui" (por exemplo a lista ainda não carregou), não apaga nada no servidor.
    final del = ops.values.where((o) => o == MirrorOp.deleteRemote).length;
    final skipDeletes = del > 2 && del * 2 > meta.length;

    final need = [for (final e in ops.entries) if (e.value == MirrorOp.pull || e.value == MirrorOp.merge) e.key];
    final got = <String, MirrorItem>{};
    for (var i = 0; i < need.length; i += 10) {
      final r = await links.miGet(code, secret, need.sublist(i, (i + 10).clamp(0, need.length)));
      if (!r.ok) return;
      got.addAll(r.items);
    }

    var any = false;
    for (final e in ops.entries) {
      final sec = e.key;
      switch (e.value) {
        case MirrorOp.pull:
        case MirrorOp.merge:
          final item = got[sec];
          if (item == null || item.d == null) continue;
          applying = true;
          try {
            apply(sec, item.d!, merge: e.value == MirrorOp.merge);
          } finally {
            applying = false;
          }
          any = true;
          if (e.value == MirrorOp.pull) {
            final now = build()[sec];
            meta[sec] = MirrorMeta(now?.hash ?? mirrorHash(item.d!), item.u);
          } else {
            await _push(code, secret, sec, remote[sec]?.u ?? 0);
          }
        case MirrorOp.push:
          await _push(code, secret, sec, remote[sec]?.u ?? 0);
        case MirrorOp.deleteRemote:
          if (skipDeletes) continue;
          final u = _nextVersion(remote[sec]?.u ?? 0);
          final r = await links.miDel(code, secret, sec, u);
          if (r.ok) meta.remove(sec);
        case MirrorOp.deleteLocal:
          applying = true;
          try {
            deleteLocal(sec);
          } finally {
            applying = false;
          }
          meta.remove(sec);
          any = true;
      }
    }
    rev = list.mirrorRev;
    _saveMeta();
    if (any) changed();
  }

  int _nextVersion(int remoteU) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > remoteU ? now : remoteU + 1;
  }

  Future<void> _push(String code, String secret, String sec, int remoteU) async {
    final cur = build()[sec];
    if (cur == null) return;
    if (cur.data.length > kMaxSectionChars) {
      onNote?.call(sec); // grande demais para o espelho: segue só neste aparelho
      return;
    }
    final u = _nextVersion(remoteU);
    final r = await links.miPut(code, secret, sec, u, cur.data);
    if (r.ok && !r.stale) meta[sec] = MirrorMeta(cur.hash, u);
  }
}
