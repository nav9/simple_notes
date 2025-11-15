// session_manager.dart
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();

  factory SessionManager() => _instance;

  SessionManager._internal();

  // Optional global session password (can be used for prefill UI etc)
  String? sessionPassword;

  // App default export path in this session
  String? defaultExportPath;

  // Last successful export path
  String? lastExportPath;

  // --- In-memory per-note password storage (never persisted) ---
  final Map<dynamic, String> _notePasswords = {};

  void storeNotePassword(dynamic noteKey, String password) {
    if (noteKey == null) return;
    _notePasswords[noteKey] = password;
  }

  String? getNotePassword(dynamic noteKey) {
    if (noteKey == null) return null;
    return _notePasswords[noteKey];
  }

  void clearNotePassword(dynamic noteKey) {
    if (noteKey == null) return;
    _notePasswords.remove(noteKey);
  }

  void clearAllNotePasswords() {
    _notePasswords.clear();
  }
}
