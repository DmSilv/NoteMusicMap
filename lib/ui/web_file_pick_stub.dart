import 'dart:typed_data';

/// Fora do navegador o seletor é o do aparelho (image_picker); esta função só existe para o código compilar nas duas pontas.
Future<Uint8List?> pickImageBytesWeb({required bool camera}) async => null;
