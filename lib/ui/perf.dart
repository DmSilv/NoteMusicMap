import 'package:flutter/foundation.dart';

class _NeverNotifies extends ChangeNotifier {}

/// Um [Listenable] que nunca avisa nada. Uma aba escondida escuta este em vez do
/// app: assim ela não se reconstrói enquanto não está na tela, e volta a
/// atualizar sozinha (o ListenableBuilder reassina) quando fica visível.
final Listenable kNeverNotifies = _NeverNotifies();
