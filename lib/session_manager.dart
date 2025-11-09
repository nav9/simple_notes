class SessionManager {
  static final SessionManager _instance = SessionManager._internal();

  factory SessionManager() {
    return _instance;
  }

  SessionManager._internal();

  // Stores password for encryption/decryption during the session
  String? sessionPassword;

  // Stores the app's default, non-changeable export directory path
  String? defaultExportPath;

  // Stores the path of the last successful export for the session
  String? lastExportPath;
}