/// Estado do vínculo online em linguagem simples: o que está acontecendo com a conexão,
/// o que isso significa para a pessoa e o que ela pode fazer. Dart puro e testável.
library;

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
  if (d.inSeconds < 45) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes < 1 ? 1 : d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  final days = d.inDays;
  return 'há $days ${days == 1 ? 'dia' : 'dias'}';
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
      : ' ${queued == 1 ? '1 item espera' : '$queued itens esperam'} na fila de envio e ${queued == 1 ? 'vai' : 'vão'} quando a conexão voltar.';
  if (!enabled) {
    return LinkStatusInfo(
      LinkHealth.off,
      'Desligado',
      'Nada é enviado nem recebido. Suas aulas, tarefas e agenda continuam neste aparelho.'
      '${queued > 0 ? ' O que está na fila fica guardado até você ligar.' : ''} '
      'Ligue para falar com seu professor ou seus alunos.',
      canReconnect: false,
    );
  }
  if (serverUnavailable) {
    return LinkStatusInfo(
      LinkHealth.serverDown,
      'Servidor indisponível',
      'O servidor não está respondendo agora. O que você fizer fica guardado.$queue '
      'Tente "Reconectar agora" em alguns minutos.',
      canReconnect: true,
    );
  }
  if (online == false) {
    return LinkStatusInfo(
      LinkHealth.offline,
      'Sem conexão',
      'Não consegui falar com o servidor: pode ser a internet ou uma instabilidade.$queue '
      'Se a internet está boa, toque em "Reconectar agora".',
      canReconnect: true,
    );
  }
  if (online == null) {
    return const LinkStatusInfo(
      LinkHealth.connecting,
      'Conectando…',
      'Falando com o servidor. Isso leva alguns segundos.',
      canReconnect: true,
    );
  }
  final when = lastOkAt == null ? '' : ' Última atualização ${fmtAgo(now.difference(lastOkAt))}.';
  return LinkStatusInfo(
    LinkHealth.online,
    'Conectado',
    'Tudo certo: aulas, tarefas e agenda chegam sozinhas.$when$queue',
    canReconnect: true,
  );
}
