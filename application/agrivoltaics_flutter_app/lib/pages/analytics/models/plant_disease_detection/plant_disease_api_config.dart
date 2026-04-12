// Base URL for the plant disease FastAPI service (no trailing slash).
//
// Default targets the host loopback interface. Examples:
// - Android emulator (API on host): --dart-define=PLANT_DISEASE_API_BASE=http://10.0.2.2:8000
// - Physical device (API on same LAN): --dart-define=PLANT_DISEASE_API_BASE=http://192.168.x.x:8000
// - Full predict URL: --dart-define=PLANT_DISEASE_PREDICT_URL=http://host:8000/predict (overrides base)

const String _kDefaultApiBase = 'http://127.0.0.1:8000';

String get plantDiseasePredictUrl {
  const predictOverride = String.fromEnvironment(
    'PLANT_DISEASE_PREDICT_URL',
    defaultValue: '',
  );
  if (predictOverride.isNotEmpty) {
    return predictOverride;
  }
  const base = String.fromEnvironment(
    'PLANT_DISEASE_API_BASE',
    defaultValue: _kDefaultApiBase,
  );
  final trimmed = base.replaceAll(RegExp(r'/+$'), '');
  return '$trimmed/predict';
}
