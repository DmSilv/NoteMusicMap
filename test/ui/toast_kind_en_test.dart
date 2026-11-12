// O tipo do aviso em inglês (sai de palavras-chave, como no português: veja toast_kind_test.dart).
import 'package:afina/ui/toast_kind.dart';
import 'package:afina_core/afina_core.dart' show AppLang, Lang;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => Lang.current = AppLang.en);
  tearDown(() => Lang.current = AppLang.pt);

  test('confirmações de ação são sucesso', () {
    for (final m in [
      'Lesson updated.',
      'Lesson canceled.',
      'Material saved.',
      'Task saved.',
      'Code copied.',
      'Invite copied. Paste it in a chat to send.',
      'Sent to Ana.',
      "Ana linked. They now see you as a teacher.",
      'Online link on.',
      'Profile restored.',
      'Lock removed',
      'History erased',
      "Absence recorded on Ana's profile.",
      'Absence recorded. The lesson was canceled and Ana was notified.',
      'Imported: 2 new methods and 5 lessons.',
      'Slot secured!',
    ]) {
      expect(toastKindOf(m), ToastKind.success, reason: m);
    }
  });

  test('problemas e limites são atenção', () {
    for (final m in [
      "I couldn't open the link.",
      "Couldn't open Meet.",
      'There are no lessons in that period.',
      'No connection: I\'ll link Ana as soon as the internet is back.',
      "Online link off. You're offline.",
      'Conflicts with the lesson of Bia. Pick another time.',
      'That time has already passed. Pick a date from today on.',
      'Scheduled lessons limit reached. Cancel some old ones.',
      'Use exactly 4 digits',
      'Invalid code. Check it with your teacher.',
      "Couldn't send right now.",
      "The server didn't accept the activation. Try again.",
    ]) {
      expect(toastKindOf(m), ToastKind.warning, reason: m);
    }
  });

  test('o resto é informação', () {
    for (final m in [
      'Microphone on. Play a note!',
      'Starting lesson…',
      'Tap a lit note to remove it.',
    ]) {
      expect(toastKindOf(m), ToastKind.info, reason: m);
    }
  });
}
