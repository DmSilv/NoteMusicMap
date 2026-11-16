/// Instrumentos que o professor ensina e o que cada um já traz de sugestão: métodos e livros de estudo e repertório.
/// O professor escolhe o(s) instrumento(s) uma vez; ao passar uma tarefa de método ou de repertório, as sugestões
/// do instrumento do aluno aparecem prontas. São só TÍTULOS (nunca partituras nem trechos de obras), em Dart puro e testável.
library;

import 'i18n.dart';

class TeachingInstrument {
  final String id;
  final String _label;

  /// Métodos, livros e coleções de estudo, dos mais usados no começo para os mais avançados.
  final List<String> methods;

  /// Peças e obras muito dadas em aula.
  final List<String> repertoire;
  const TeachingInstrument(this.id, this._label, {required this.methods, required this.repertoire});

  String get label => tr(_label);
}

const List<TeachingInstrument> kTeachingInstruments = [
  TeachingInstrument(
    'violino',
    /*tr*/'Violino',
    methods: ['Suzuki', 'Wohlfahrt', 'Kayser', 'Mazas', 'Sitt', 'Hohmann', 'Dont', 'Kreutzer', 'Schradieck', 'Ševčík', 'Flesch (escalas)', 'Fiorillo', 'Rode (24 Caprichos)', 'Paganini (24 Caprichos)'],
    repertoire: [
      'Minueto em Sol (Bach)',
      'Gavota (Gossec)',
      'Concerto em Lá menor (Vivaldi)',
      'Concerto em Sol menor (Vivaldi)',
      'Concerto para dois violinos (Bach)',
      'Méditation de Thaïs (Massenet)',
      'Czardas (Monti)',
      'Canon em Ré (Pachelbel)',
      'As Quatro Estações (Vivaldi)',
      'Ave Maria (Schubert)',
      'Concertino em Ré (Küchler)',
    ],
  ),
  TeachingInstrument(
    'viola',
    /*tr*/'Viola',
    methods: ['Suzuki (Viola)', 'Kayser', 'Wohlfahrt', 'Campagnoli', 'Kreutzer', 'Palaschko', 'Ševčík'],
    repertoire: [
      'Suítes para violoncelo (Bach)',
      'Concerto em Ré (Hoffmeister)',
      'Sonata Arpeggione (Schubert)',
      'Canon em Ré (Pachelbel)',
      'O Cisne (Saint-Saëns)',
      'Elegia (Glinka)',
    ],
  ),
  TeachingInstrument(
    'violoncelo',
    /*tr*/'Violoncelo',
    methods: ['Suzuki (Violoncelo)', 'Dotzauer', 'Lee (40 Estudos)', 'Duport (21 Estudos)', 'Popper (Alta Escola)', 'Feuillard', 'Cossmann', 'Grützmacher', 'Piatti (12 Caprichos)'],
    repertoire: [
      'Suítes para violoncelo (Bach)',
      'O Cisne (Saint-Saëns)',
      'Sonata em Mi menor (Vivaldi)',
      'Concerto em Dó (Haydn)',
      'Allegro Appassionato (Saint-Saëns)',
      'Élégie (Fauré)',
      'Kol Nidrei (Bruch)',
    ],
  ),
  TeachingInstrument(
    'contrabaixo',
    /*tr*/'Contrabaixo',
    methods: ['Suzuki (Contrabaixo)', 'Simandl (Nova Escola)', 'Hrabě', 'Bille', 'Sturm', 'Zimmermann'],
    repertoire: ['O Elefante (Saint-Saëns)', 'Sonata em Sol menor (Eccles)', 'Concerto em Ré (Dittersdorf)', 'Gavota (Gossec)'],
  ),
  TeachingInstrument(
    'piano',
    /*tr*/'Piano',
    methods: [
      'Hanon (O Pianista Virtuoso)',
      'Czerny',
      'Burgmüller (25 Estudos Fáceis)',
      'Beyer (Método Preparatório)',
      'Bastien',
      'Thompson (Curso Moderno)',
      'Pozzoli',
      'Schmitt',
      'Cramer',
      'Clementi (Gradus ad Parnassum)',
      'Bartók (Mikrokosmos)',
    ],
    repertoire: [
      'Minueto em Sol (Bach)',
      'Pequeno Caderno de Anna Magdalena (Bach)',
      'Für Elise (Beethoven)',
      'Sonatina Op. 36 nº 1 (Clementi)',
      'Prelúdio em Dó, BWV 846 (Bach)',
      'Gymnopédie nº 1 (Satie)',
      'Clair de Lune (Debussy)',
      'Rêverie (Debussy)',
      'Noturno Op. 9 nº 2 (Chopin)',
      'Valsa do Minuto (Chopin)',
      'Sonata ao Luar, 1º mov. (Beethoven)',
      'Canon em Ré (Pachelbel)',
    ],
  ),
  TeachingInstrument(
    'violao',
    /*tr*/'Violão',
    methods: ['Carlevaro (Escuela de la Guitarra)', 'Sagreras (Lecciones)', 'Carcassi (25 Estudos Melódicos)', 'Giuliani (120 Arpejos)', 'Sor (Estudos)', 'Aguado', 'Tárrega', 'Pujol', 'Villa-Lobos (12 Estudos)', 'Brouwer (Estudos Simples)'],
    repertoire: [
      'Romance (Anônimo)',
      'Lágrima (Tárrega)',
      'Adelita (Tárrega)',
      'Capricho Árabe (Tárrega)',
      'Recuerdos de la Alhambra (Tárrega)',
      'Estudo em Mi menor (Sor)',
      'Prelúdio nº 1 (Villa-Lobos)',
      'Asturias (Albéniz)',
    ],
  ),
  TeachingInstrument(
    'flauta',
    /*tr*/'Flauta',
    methods: ['Köhler', 'Gariboldi', 'Berbiguier', 'Altès', 'Andersen', 'Taffanel e Gaubert (17 Exercícios Diários)', 'Moyse (De la sonorité)', 'Wye (Practice Books)'],
    repertoire: ['Badinerie (Bach)', 'Sicilienne (Fauré)', 'Pavane (Fauré)', 'Concerto em Sol (Mozart)', 'Concertino (Chaminade)', 'Syrinx (Debussy)', 'Sonata em Mi bemol (Bach)'],
  ),
  TeachingInstrument(
    'canto',
    /*tr*/'Canto',
    methods: ['Vaccai (Método Prático)', 'Concone (50 Lições)', 'Panofka', 'Marchesi'],
    repertoire: ['24 Árias Italianas', 'Caro mio ben (Giordani)', 'Se tu m’ami (Pergolesi)', 'Sebben, crudele (Caldara)', 'Amarilli, mia bella (Caccini)', 'Ave Maria (Schubert)', 'O mio babbino caro (Puccini)'],
  ),
  TeachingInstrument(
    'bateria',
    /*tr*/'Bateria e percussão',
    methods: ['Stick Control (Stone)', 'Syncopation (Reed)', 'Rudimentos (PAS)', 'Master Studies (Morello)'],
    repertoire: [],
  ),
  TeachingInstrument(
    'teoria',
    /*tr*/'Teoria e solfejo',
    methods: ['Bona (Divisão Musical)', 'Pozzoli (Solfejos)', 'Teoria da Música (Bohumil Med)', 'Compêndio de Teoria (Osvaldo Lacerda)', 'Lavignac'],
    repertoire: [],
  ),
];

/// O instrumento pelo id, ou null.
TeachingInstrument? teachingById(String? id) {
  for (final i in kTeachingInstruments) {
    if (i.id == id) return i;
  }
  return null;
}

/// Só ids que existem, sem repetir e na ordem do catálogo (o que vem de um backup ou de um aluno antigo pode ser qualquer coisa).
List<String> cleanTeachingIds(Iterable<Object?>? ids) {
  final want = {for (final x in ids ?? const <Object?>[]) if (x is String) x};
  return [for (final i in kTeachingInstruments) if (want.contains(i.id)) i.id];
}

List<String> _merge(Iterable<String> ids, List<String> Function(TeachingInstrument) pick) {
  final out = <String>[];
  final seen = <String>{};
  for (final id in ids) {
    for (final s in pick(teachingById(id) ?? const TeachingInstrument('', '', methods: [], repertoire: []))) {
      if (seen.add(s.toLowerCase())) out.add(s);
    }
  }
  return out;
}

/// Métodos e livros sugeridos para os instrumentos [ids] (sem repetir).
List<String> catalogMethods(Iterable<String> ids) => _merge(ids, (i) => i.methods);

/// Repertório sugerido para os instrumentos [ids] (sem repetir).
List<String> catalogRepertoire(Iterable<String> ids) => _merge(ids, (i) => i.repertoire);

/// Qual instrumento usar na tarefa de [studentInstrument]: o do aluno, se o professor ensina; senão o único que ele ensina; senão nenhum.
String? instrumentForTask({required String? studentInstrument, required List<String> teaches}) {
  if (studentInstrument != null && teaches.contains(studentInstrument)) return studentInstrument;
  if (teaches.length == 1) return teaches.first;
  return null;
}
