/// Estado do vínculo online em linguagem simples: o que está acontecendo com a conexão,
/// o que isso significa para a pessoa e o que ela pode fazer. Dart puro e testável.
library;

import 'i18n.dart';

enum LinkHealth {
  /// Desligado pela pessoa.
  off,

  /// Ligado, ainda sem resposta do servidor.
  connecting,

  /// Falando com o servidor.
  online,

  /// Ligado, mas sem conseguir falar com o servidor (internet ou instabilidade).
  offline,

  /// O servidor está sem o recurso configurado.
  serverDown,
}

class LinkStatusInfo {
  final LinkHealth health;
  final String title;
  final String text;

  /// Tem sentido oferecer "Reconectar agora".
  final bool canReconnect;

  const LinkStatusInfo(this.health, this.title, this.text, {required this.canReconnect});
}

/// "agora", "há 3 min", "há 2 h", "há 4 dias".
String fmtAgo(Duration d) {
  if (d.inSeconds < 45) return tr('agora');
  if (d.inMinutes < 60) return tr('há {0} min', [d.inMinutes < 1 ? 1 : d.inMinutes]);
  if (d.inHours < 24) return tr('há {0} h', [d.inHours]);
  final days = d.inDays;
  return tr('há {0} {1}', [days, days == 1 ? tr('dia') : tr('dias')]);
}

/// Resume o vínculo: [enabled] (ligado pela pessoa), [serverUnavailable] (servidor sem o recurso),
/// [online] (true = respondeu, false = falhou, null = ainda não sabe), [queued] (itens esperando
/// envio) e [lastOkAt] (última resposta boa).
LinkStatusInfo describeLink({
  required bool enabled,
  required bool serverUnavailable,
  required bool? online,
  required int queued,
  DateTime? lastOkAt,
  required DateTime now,
}) {
  final queue = queued <= 0
      ? ''
      : tr(' {0} na fila de envio e {1} quando a conexão voltar.', [queued == 1 ? tr('1 item espera') : tr('{0} itens esperam', [queued]), queued == 1 ? tr('vai') : tr('vão')]);
  if (!enabled) {
    return LinkStatusInfo(
      LinkHealth.off,
      tr('Desligado'),
      tr('Nada é enviado nem recebido. Suas aulas, tarefas e agenda continuam neste aparelho.{0} Ligue para falar com seu professor ou seus alunos.', [queued > 0 ? tr(' O que está na fila fica guardado até você ligar.') : '']),
      canReconnect: false,
    );
  }
  if (serverUnavailable) {
    return LinkStatusInfo(
      LinkHealth.serverDown,
      tr('Servidor indisponível'),
      tr('O servidor não está respondendo agora. O que você fizer fica guardado.{0} Tente "Reconectar agora" em alguns minutos.', [queue]),
      canReconnect: true,
    );
  }
  if (online == false) {
    return LinkStatusInfo(
      LinkHealth.offline,
      tr('Sem conexão'),
      tr('Não consegui falar com o servidor: pode ser a internet ou uma instabilidade.{0} Se a internet está boa, toque em "Reconectar agora".', [queue]),
      canReconnect: true,
    );
  }
  if (online == null) {
    return LinkStatusInfo(
      LinkHealth.connecting,
      tr('Conectando…'),
      tr('Falando com o servidor. Isso leva alguns segundos.'),
      canReconnect: true,
    );
  }
  final when = lastOkAt == null ? '' : tr(' Última atualização {0}.', [fmtAgo(now.difference(lastOkAt))]);
  return LinkStatusInfo(
    LinkHealth.online,
    tr('Conectado'),
    tr('Tudo certo: aulas, tarefas e agenda chegam sozinhas.{0}{1}', [when, queue]),
    canReconnect: true,
  );
}
