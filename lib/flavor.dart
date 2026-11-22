/// true in the Google Play build (flutter build ... --dart-define=PLAY=true).
/// The Play build has no YouTube downloading / stream extraction, no accessibility-service lock and no "all files" access.
const bool kPlay = bool.fromEnvironment('PLAY', defaultValue: false);
