// Tipo, cor e duração dos avisos curtos: sucesso, atenção e informação.
import 'package:afina/ui/toast_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmações de ação são sucesso', () {
    for (final m in [
      'Aula atualizada.',
      'Aula cancelada.',
      'Material salvo.',
      'Tarefa salva.',
      'Código copiado.',
      'Convite copiado. Cole numa conversa para enviar.',
      'Enviado para Ana.',
      'Ana vinculado. Ele já vê você como professor.',
      'Vínculo online ligado.',
      'Perfil restaurado.',
      'Trava removida',
      'Histórico apagado',
      'Falta registrada na ficha de Ana.',
      'Falta registrada. A aula foi cancelada e Ana foi avisado.',
    ]) {
      expect(toastKindOf(m), ToastKind.success, reason: m);
    }
  });

  test('problemas e limites são atenção', () {
    for (final m in [
      'Não consegui abrir o link.',
      'Não foi possível abrir o Meet.',
      'Não há aulas nesse período.',
      'Use exatamente 4 números',
      'Sem conexão: vou vincular Ana assim que a internet voltar.',
      'Vínculo online desligado. Você está offline.',
      'Choca com a aula de Bia. Escolha outro horário.',
      'Esse horário já passou. Escolha uma data de hoje em diante.',
      'Limite de aulas marcadas atingido.',
    ]) {
      expect(toastKindOf(m), ToastKind.warning, reason: m);
    }
  });

  test('o resto é informação', () {
    for (final m in ['Esse método já estava na lista.', 'Sua lista está vazia.', 'Há uma versão nova do app.']) {
      expect(toastKindOf(m), ToastKind.info, reason: m);
    }
  });

  test('atenção vence sucesso quando a frase tem os dois jeitos ("Não consegui salvar")', () {
    expect(toastKindOf('Não consegui salvar agora.'), ToastKind.warning);
  });

  test('cada tipo tem cor e ícone próprios', () {
    final cores = {for (final k in ToastKind.values) toastColorOf(k)};
    final icones = {for (final k in ToastKind.values) toastIconOf(k)};
    expect(cores.length, 3);
    expect(icones.length, 3);
  });

  test('o tempo na tela cresce com a frase e é maior na atenção', () {
    final curta = toastDuration('Aula salva.', ToastKind.success);
    final longa = toastDuration('Convite copiado. Cole numa conversa para enviar a quem você quer convidar.', ToastKind.success);
    expect(curta, const Duration(milliseconds: 3000), reason: 'sucesso curto: 3 s (antes era 2,6 s)');
    expect(longa > curta, isTrue);
    expect(toastDuration('Aula salva.', ToastKind.warning) > curta, isTrue);
    expect(toastDuration('x' * 500, ToastKind.warning) < const Duration(seconds: 12), isTrue, reason: 'nunca fica na tela para sempre');
  });
}
