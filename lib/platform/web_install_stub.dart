/// Fora da web (app nativo) não há o que instalar pelo navegador.
bool webIsStandalone() => true;
bool webIsMobileBrowser() => false;
bool webIsAndroidBrowser() => false;
bool webCanPromptInstall() => false;
Future<bool> webPromptInstall() async => false;
void webOnInstallEvents(void Function() onChange) {}
