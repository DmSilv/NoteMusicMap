/// Fora da web não há vibração de navegador (o plugin nativo cuida disso).
bool webVibrationSupported() => false;
bool webIsIos() => false;
bool webVibrate(List<int> pattern) => false;
