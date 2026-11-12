/// Acervo e Repertório do professor: só LINKS (Google Drive, IMSLP, YouTube…), nenhum arquivo é guardado.
/// A mesma lista de sites aceitos existe no servidor (api/_lib/library.js): mantenha as duas iguais.
library;

import 'input_guard.dart';
import 'i18n.dart';

/// Sites aceitos (https). Subdomínios valem.
final List<String> kLibraryHosts = [
  'drive.google.com',
  'docs.google.com',
  'dropbox.com',
  'onedrive.live.com',
  '1drv.ms',
  'imslp.org',
  'cpdl.org',
  'youtube.com',
  'youtu.be',
];

const int kLibMaxItems = 200;

/// Endereço aceito ou null (só https, só os sites da lista, sem usuário e senha).
String? libraryUrl(String? raw) {
  final s = (raw ?? '').trim();
  if (s.length < 12 || s.length > 500 || RegExp(r'''[\s<>"'`\\]''').hasMatch(s)) return null;
  final u = Uri.tryParse(s);
  if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty || !u.hasAuthority) return null;
  final host = u.host.toLowerCase();
  final ok = kLibraryHosts.any((h) => host == h || host.endsWith('.$h'));
  return ok ? u.toString() : null;
}

/// Um item do acervo (k: 'a' = acervo de métodos, 'r' = repertório de peças).
class LibItem {
  final String id;
  final String kind; // 'a' ou 'r'
  final String folder;
  final String title;
  final String author;
  final String url;
  final String note;

  /// null = todos os alunos; senão, só estes códigos.
  final List<String>? to;

  /// Escondido pela moderação (o professor continua vendo).
  final bool hidden;
  final int created;
  final int modified;
  LibItem({
    required this.id,
    this.kind = 'a',
    this.folder = /*tr*/'Geral',
    required this.title,
    this.author = '',
    required this.url,
    this.note = '',
    this.to,
    this.hidden = false,
    this.created = 0,
    this.modified = 0,
  });

  bool get isRepertoire => kind == 'r';

  LibItem copyWith({String? kind, String? folder, String? title, String? author, String? url, String? note, List<String>? to, bool clearTo = false}) =>
      LibItem(
        id: id,
        kind: kind ?? this.kind,
        folder: folder ?? this.folder,
        title: title ?? this.title,
        author: author ?? this.author,
        url: url ?? this.url,
        note: note ?? this.note,
        to: clearTo ? null : (to ?? this.to),
        hidden: hidden,
        created: created,
        modified: modified,
      );

  /// O que vai ao servidor ao salvar (com a declaração do professor).
  Map<String, dynamic> toWire() => {
        'id': id,
        'k': kind,
        'f': folder,
        't': title,
        if (author.isNotEmpty) 'a': author,
        'u': url,
        if (note.isNotEmpty) 'n': note,
        if (to != null) 'to': to,
        if (created > 0) 'c': created,
        'ok': true,
      };

  static LibItem? tryFrom(Object? x) {
    try {
      final m = (x as Map).cast<String, dynamic>();
      final id = m['id'] as String? ?? '';
      if (!RegExp(r'^[a-z0-9]{2,40}$').hasMatch(id)) return null;
      final u = libraryUrl(m['u'] as String?);
      final t = cleanText(m['t'] as String?, max: 80);
      if (u == null || t.isEmpty) return null;
      final to = m['to'];
      return LibItem(
        id: id,
        kind: m['k'] == 'r' ? 'r' : 'a',
        folder: cleanText(m['f'] as String?, max: 40).isEmpty ? tr('Geral') : cleanText(m['f'] as String?, max: 40),
        title: t,
        author: cleanText(m['a'] as String?, max: 60),
        url: u,
        note: cleanText(m['n'] as String?, max: 300),
        to: to is List ? [for (final c in to.take(40)) if (c is String) c] : null,
        hidden: m['x'] == 1 || m['x'] == true,
        created: (m['c'] as num?)?.toInt() ?? 0,
        modified: (m['m'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Pastas existentes (na ordem em que aparecem) dos itens de um tipo.
List<String> libraryFolders(Iterable<LibItem> items, {String? kind}) {
  final out = <String>[];
  for (final i in items) {
    if (kind != null && i.kind != kind) continue;
    if (!out.contains(i.folder)) out.add(i.folder);
  }
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

/// Uma tarefa "Material do professor" aponta para o acervo: [subject] é o título do item (ou da pasta, ou
/// vazio = acervo todo) e [detail] é a pasta. Nada novo vai ao servidor: é o texto da própria tarefa.
/// Texto de uma tarefa que aponta para o acervo inteiro.
final String kMaterialAll = tr('Material do professor');

/// A pasta padrão é gravada como "Geral" (dado); na tela aparece no idioma de hoje. Pastas que o professor criou ficam como estão.
String folderLabel(String folder) => folder == 'Geral' ? tr('Geral') : folder;

class MaterialRef {
  /// Título do item procurado (vazio = só a pasta, ou o acervo todo).
  final String title;
  final String folder;
  const MaterialRef({this.title = '', this.folder = ''});

  /// A partir do texto da tarefa ([subject] e [detail]); "Material do professor" = acervo todo.
  factory MaterialRef.fromTask(String subject, String detail) =>
      subject.trim() == kMaterialAll ? const MaterialRef() : MaterialRef(title: subject.trim(), folder: detail.trim());

  bool get isAll => title.isEmpty && folder.isEmpty;

  /// Procura em [items] o que a tarefa pede: o item exato (título e pasta) > a pasta inteira > null (acervo todo).
  LibMatch resolve(List<LibItem> items) {
    String norm(String s) => s.trim().toLowerCase();
    if (title.isNotEmpty) {
      final exact = items.where((i) => norm(i.title) == norm(title) && (folder.isEmpty || norm(i.folder) == norm(folder))).toList();
      if (exact.isNotEmpty) return LibMatch(item: exact.first, folder: exact.first.folder);
      // O assunto pode ser o nome de uma pasta (tarefa "pasta inteira").
      final asFolder = items.where((i) => norm(i.folder) == norm(title)).toList();
      if (asFolder.isNotEmpty) return LibMatch(folder: asFolder.first.folder);
    }
    if (folder.isNotEmpty) {
      final f = items.where((i) => norm(i.folder) == norm(folder)).toList();
      if (f.isNotEmpty) return LibMatch(folder: f.first.folder);
    }
    return const LibMatch();
  }

  /// "Wohlfahrt · Estudos op. 45" / "Wohlfahrt" / "Material do professor".
  String get label {
    if (isAll) return tr('Material do professor');
    if (title.isEmpty) return folder;
    return folder.isEmpty || folder == title ? title : '$title · $folder';
  }
}

/// Resultado de [MaterialRef.resolve]: o item (se achou), a pasta para filtrar, ou nada (acervo todo).
class LibMatch {
  final LibItem? item;
  final String folder;
  const LibMatch({this.item, this.folder = ''});
  bool get found => item != null || folder.isNotEmpty;
}
