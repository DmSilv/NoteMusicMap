/// Fora da web não há cache de página para limpar.
Future<void> clearWebCachesAndReload() async {}

/// Fora da web não há cache de página: atualizar é pela loja de aplicativos.
Future<bool> updateWebAppAndReload() async => false;
