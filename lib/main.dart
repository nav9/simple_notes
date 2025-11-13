import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as p;
import 'session_manager.dart'; // Ensure this file exists in lib/

// --- SERVICES (Encryption) ---

class EncryptionService {
  // FIX: Use a fixed, non-random IV.
  // Using a random IV on each app start (IV.fromLength(16)) was causing the decryption to fail after a restart.
  // The IV must be the same for both encryption and decryption.
  // NOTE: For production-grade security, a unique IV should be generated per-encryption and stored alongside the ciphertext.
  // For simplicity in this app, we use a single, hardcoded IV.
  static final iv = encrypt.IV.fromBase64('AAAAAAAAAAAAAAAAAAAAAA=='); // A fixed 16-byte zero IV

  static String encryptText(String text, String password) {
    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    return "[ENCRYPTED]" + encrypted.base64;
  }

  static String? decryptText(String encryptedText, String password) {
    if (!encryptedText.startsWith("[ENCRYPTED]")) return null;
    try {
      final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted = encrypter.decrypt64(encryptedText.substring(11), iv: iv);
      return decrypted;
    } catch (e) {
      // This will catch errors from wrong passwords or corrupted data.
      return null;
    }
  }
}

// --- APP INITIALIZATION ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);
  await Hive.openBox<Map>('notesBox');
  runApp(SimpleNotesApp());
}

// --- MAIN APP WIDGET ---

class SimpleNotesApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Notes',
      theme: ThemeData.light(),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.grey[850],
        appBarTheme: AppBarTheme(color: Colors.grey[900]),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Colors.blueGrey),
        textTheme: const TextTheme(bodyLarge: TextStyle(color: Colors.white), bodyMedium: TextStyle(color: Colors.white70), labelLarge: TextStyle(color: Colors.white)),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.grey[800], border: OutlineInputBorder(), labelStyle: TextStyle(color: Colors.white)),
        listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white),
      ),
      themeMode: ThemeMode.dark,
      home: NotesListScreen(),
    );
  }
}

// --- NOTES LIST SCREEN WIDGET ---

class NotesListScreen extends StatefulWidget {
  @override
  _NotesListScreenState createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  late Box<Map> notesBox;
  final Map<dynamic, String> _decryptedNotesCache = {}; // key = Hive key

  @override
  void initState() {
    super.initState();
    notesBox = Hive.box<Map>('notesBox');
  }

  void _deleteNoteConfirmation(int index) {
    showDialog(
      context: context,
      // FIX: Use a specific context for the dialog to ensure correct dismissal.
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete confirmation'),
        content: const Text('This will delete the note from the app. Exported files will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text('No')),
          TextButton(
            onPressed: () async {
              final key = notesBox.keyAt(index);
              await notesBox.deleteAt(index);
              _decryptedNotesCache.remove(key);
              if (mounted) setState(() {});
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _importNotes() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          final content = await File(file.path!).readAsString();
          final isEncrypted = content.startsWith("[ENCRYPTED]");
          final newNote = {'content': content, 'isEncrypted': isEncrypted, 'filename': p.basename(file.path!)};
          await notesBox.add(newNote);
        }
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleEncryptedNoteTap(int index, Map noteData) async {
    final password = await _showPasswordDialog(context, "Enter password for '${noteData['filename']}'", false);
    if (password != null && password.isNotEmpty) {
      final decryptedContent = EncryptionService.decryptText(noteData['content'], password);
      if (decryptedContent != null) {
        final key = notesBox.keyAt(index);
        if (mounted) setState(() => _decryptedNotesCache[key] = decryptedContent);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Notes', style: TextStyle(color: Colors.white70)),
        actions: [IconButton(icon: const Icon(Icons.file_open), tooltip: 'Import Note(s)', onPressed: _importNotes)],
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Map> box, _) {
          if (box.values.isEmpty) return Center(child: Text('Add or import a note', style: Theme.of(context).textTheme.bodyLarge));
          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final noteData = box.getAt(index)!;
              final key = box.keyAt(index);
              final isEncrypted = noteData['isEncrypted'] ?? false;

              String displayContent;
              if (isEncrypted) {
                displayContent = _decryptedNotesCache[key] ?? "🔒 Encrypted: ${noteData['filename']}";
              } else {
                displayContent = noteData['content'];
              }
              return Card(
                child: ListTile(
                  title: Text(displayContent, style: const TextStyle(color: Colors.white38), maxLines: 3, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    final key = box.keyAt(index);
                    if (isEncrypted && !_decryptedNotesCache.containsKey(key)) {
                      _handleEncryptedNoteTap(index, noteData);
                    } else {
                      final content = _decryptedNotesCache[key] ?? noteData['content'];
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => EditNoteScreen(index: index, note: content)));
                    }
                  },
                  leading: IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteNoteConfirmation(index), color: Colors.red[900]),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(child: const Icon(Icons.add, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditNoteScreen()))),
    );
  }
}

// --- EDIT NOTE SCREEN WIDGET ---

class EditNoteScreen extends StatefulWidget {
  final int? index;
  final String? note;
  EditNoteScreen({this.index, this.note});
  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
    // Automatically focus the text field if this is a new note.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.note == null || widget.note!.isEmpty) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveNote() {
    final notesBox = Hive.box<Map>('notesBox');
    final content = _controller.text;
    final isEncrypted = content.startsWith("[ENCRYPTED]");
    final newNote = {'content': content, 'isEncrypted': isEncrypted, 'filename': isEncrypted ? 'Encrypted Note' : 'Internal Note'};
    if (widget.index != null) {
      notesBox.putAt(widget.index!, newNote);
    } else {
      final List<Map> tempList = [newNote];
      tempList.addAll(notesBox.values);
      notesBox.clear().then((_) => notesBox.addAll(tempList));
    }
    Navigator.pop(context);
  }

  Future<void> _toggleEncryption() async {
    final currentText = _controller.text;
    final isCurrentlyEncrypted = currentText.startsWith("[ENCRYPTED]");
    if (isCurrentlyEncrypted) {
      final password = await _showPasswordDialog(context, "Enter password to decrypt note", false);
      if (password != null && password.isNotEmpty) {
        final decryptedText = EncryptionService.decryptText(currentText, password);
        if (decryptedText != null) {
          if (mounted) setState(() => _controller.text = decryptedText);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note decrypted successfully!')));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')));
        }
      }
    } else {
      final password = await _showPasswordDialog(context, "Set password to encrypt note", true);
      if (password != null && password.isNotEmpty) {
        final encryptedText = EncryptionService.encryptText(currentText, password);
        if (mounted) setState(() => _controller.text = encryptedText);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note encrypted successfully!')));
      }
    }
  }

  Future<void> _exportNote() async {
    final bool? success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportNoteDialog(noteContent: _controller.text),
    );
    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exported successfully!'), duration: Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder textBorder = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(4)), borderSide: BorderSide(width: 1, color: Colors.black54));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note', style: TextStyle(color: Colors.white24)),
        actions: [
          IconButton(icon: const Icon(Icons.enhanced_encryption), onPressed: _toggleEncryption, tooltip: 'Encrypt/Decrypt Note'),
          IconButton(icon: const Icon(Icons.sd_storage_outlined), onPressed: _exportNote, tooltip: 'Export Note'),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveNote, color: Colors.yellow),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(controller: _controller, focusNode: _focusNode, maxLines: null, decoration: InputDecoration(hintText: 'Enter your note', fillColor: Colors.black54, enabledBorder: textBorder, focusedBorder: textBorder), keyboardAppearance: Brightness.dark, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}

// --- UTILITY DIALOGS AND WIDGETS ---

Future<String?> _showPasswordDialog(BuildContext context, String title, bool allowPrefill) {
  final passwordController = TextEditingController();
  final sessionManager = SessionManager();
  if (allowPrefill && sessionManager.sessionPassword != null) {
    passwordController.text = sessionManager.sessionPassword!;
  }
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(hintText: "Password"), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.of(context).pop(passwordController.text), child: const Text("OK")),
      ],
    ),
  );
}

class ExportNoteDialog extends StatefulWidget {
  final String noteContent;
  const ExportNoteDialog({Key? key, required this.noteContent}) : super(key: key);
  @override
  _ExportNoteDialogState createState() => _ExportNoteDialogState();
}

class _ExportNoteDialogState extends State<ExportNoteDialog> {
  final _filenameController = TextEditingController();
  final _sessionManager = SessionManager();

  bool _isSaving = false;
  String? _errorMessage;
  String _currentPath = "Loading path...";
  bool get _isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _filenameController.text = '${DateTime.now().toIso8601String().replaceAll(":", "-").replaceAll(".", "-")}.txt';
    _initializePaths();
  }

  Future<void> _initializePaths() async {
    if (_sessionManager.defaultExportPath == null) {
      Directory? dir;
      if (_isDesktop) {
        dir = await getDownloadsDirectory();
      } else {
        dir = await getExternalStorageDirectory();
      }
      _sessionManager.defaultExportPath = dir?.path ?? (await getApplicationDocumentsDirectory()).path;
    }
    if (mounted) setState(() => _currentPath = _sessionManager.lastExportPath ?? _sessionManager.defaultExportPath!);
  }

  Future<void> _doExport() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final filename = _filenameController.text.trim();
    if (filename.isEmpty) {
      setState(() {
        _errorMessage = "Filename cannot be empty.";
        _isSaving = false;
      });
      return;
    }

    try {
      // CHANGE: No longer open a file picker on desktop. Save directly.
      final finalPath = p.join(_currentPath, filename);

      // On mobile, we still need to check permissions first.
      if (!_isDesktop) {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        if (!status.isGranted) throw "Storage permission was denied.";
      }

      final file = File(finalPath);
      // Ensure the directory exists before writing.
      await file.parent.create(recursive: true);
      await file.writeAsString(widget.noteContent);

      _sessionManager.lastExportPath = p.dirname(finalPath);
      if (mounted) Navigator.of(context).pop(true);

    } catch (e) {
      setState(() {
        _errorMessage = "Failed to save file: ${e.toString()}\n\nTry selecting a different folder or check permissions.";
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Save location:', style: Theme.of(context).textTheme.bodySmall),
            Text(_currentPath, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
            const SizedBox(height: 16),
            TextField(controller: _filenameController, decoration: const InputDecoration(labelText: 'Filename')),
            if (_isDesktop)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () async {
                      final selectedPath = await FilePicker.platform.getDirectoryPath();
                      if (selectedPath != null && mounted) setState(() => _currentPath = selectedPath);
                    },
                    child: const Text('Change Folder'),
                  ),
                  TextButton(onPressed: () => setState(() => _currentPath = _sessionManager.defaultExportPath!), child: const Text('Reset')),
                ],
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  color: Colors.red[900],
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isSaving ? null : _doExport,
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Export'),
        ),
      ],
    );
  }
}