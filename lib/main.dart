import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:universal_io/io.dart'; // Used for Platform detection
import 'package:path/path.dart' as p; // Used for getting the basename of a file
import 'session_manager.dart'; // Make sure you have this file as defined previously

// --- SERVICES (Encryption) ---

class EncryptionService {
  // A static IV is used for simplicity. In a production app, generate and store a unique IV per encryption.
  static final iv = encrypt.IV.fromLength(16);

  static String encryptText(String text, String password) {
    // Pad the key to ensure it's 32 bytes for AES-256.
    final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    // Prepend a marker to easily identify encrypted content.
    return "[ENCRYPTED]" + encrypted.base64;
  }

  static String? decryptText(String encryptedText, String password) {
    // Check for the marker. If not present, it's not our encrypted format.
    if (!encryptedText.startsWith("[ENCRYPTED]")) return null;
    try {
      final key = encrypt.Key.fromUtf8(password.padRight(32, '\0'));
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      // Remove the marker before decrypting.
      final decrypted = encrypter.decrypt64(encryptedText.substring(11), iv: iv);
      return decrypted;
    } catch (e) {
      // If decryption fails (e.g., wrong password), return null.
      return null;
    }
  }
}

// --- APP INITIALIZATION ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);
  // Using a Box<Map> allows for storing structured note data.
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
  // Cache to hold decrypted notes for the current session.
  final Map<int, String> _decryptedNotesCache = {};

  @override
  void initState() {
    super.initState();
    notesBox = Hive.box<Map>('notesBox');
  }

  void _deleteNoteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete confirmation'),
        content: const Text('This will delete the note from the app. Exported files will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('No')),
          TextButton(
            onPressed: () {
              setState(() {
                notesBox.deleteAt(index);
              });
              Navigator.of(context).pop(); // This ensures the dialog closes correctly.
            },
            child: Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _importNotes() async {
    // The FilePicker itself is cross-platform. No specific logic is needed here
    // as it abstracts away the underlying OS file dialogs.
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );

    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          final content = await File(file.path!).readAsString();
          final isEncrypted = content.startsWith("[ENCRYPTED]");
          final newNote = {
            'content': content,
            'isEncrypted': isEncrypted,
            'filename': p.basename(file.path!), // Get just the filename
          };
          await notesBox.add(newNote);
        }
      }
      setState(() {}); // Refresh the UI to show imported notes
    }
  }

  Future<void> _handleEncryptedNoteTap(int index, Map noteData) async {
    final password = await _showPasswordDialog("Enter password for '${noteData['filename']}'");
    if (password != null && password.isNotEmpty) {
      final decryptedContent = EncryptionService.decryptText(noteData['content'], password);
      if (decryptedContent != null) {
        setState(() {
          // Store the decrypted content in the session cache.
          _decryptedNotesCache[index] = decryptedContent;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Notes', style: TextStyle(color: Colors.white70)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: 'Import Note(s)',
            onPressed: _importNotes,
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Map> box, _) {
          if (box.values.isEmpty) return Center(child: Text('Add or import a note', style: Theme.of(context).textTheme.bodyLarge));
          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final noteData = box.getAt(index)!;
              final isEncrypted = noteData['isEncrypted'] ?? false;
              String displayContent;

              if (isEncrypted) {
                // If the note is encrypted, check the cache first. If not found, show the filename.
                displayContent = _decryptedNotesCache[index] ?? "🔒 Encrypted: ${noteData['filename']}";
              } else {
                displayContent = noteData['content'];
              }

              return Card(
                child: ListTile(
                  title: Text(displayContent, style: const TextStyle(color: Colors.white38), maxLines: 3, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    if (isEncrypted && !_decryptedNotesCache.containsKey(index)) {
                      // If it's an encrypted note not yet unlocked, prompt for password.
                      _handleEncryptedNoteTap(index, noteData);
                    } else {
                      // Otherwise, open the editor with the (decrypted) content.
                      Navigator.push(context, MaterialPageRoute(builder: (context) => EditNoteScreen(index: index, note: displayContent)));
                    }
                  },
                  leading: IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteNoteConfirmation(index), color: Colors.red[900]),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditNoteScreen())),
      ),
    );
  }

  Future<String?> _showPasswordDialog(String title) {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(hintText: "Password")),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(passwordController.text), child: Text("OK")),
        ],
      ),
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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
  }

  void _saveNote() {
    final notesBox = Hive.box<Map>('notesBox');
    final newNote = {
      'content': _controller.text,
      'isEncrypted': false, // Notes saved internally are always plaintext.
      'filename': 'Internal Note',
    };

    if (widget.index != null) {
      notesBox.putAt(widget.index!, newNote);
    } else {
      // Add new note to the beginning of the list.
      final List<Map> tempList = [newNote];
      tempList.addAll(notesBox.values);
      notesBox.clear().then((_) => notesBox.addAll(tempList));
    }
    Navigator.pop(context);
  }

  Future<void> _exportNote() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ExportNoteDialog(),
    );

    if (result == null) return; // User cancelled the dialog.

    final bool encrypt = result['encrypt'];
    final String? password = result['password'];
    String fileContent = _controller.text;

    if (encrypt) {
      if (password == null || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password cannot be empty for encryption.')));
        return;
      }
      fileContent = EncryptionService.encryptText(_controller.text, password);
    }

    // --- PLATFORM-AWARE EXPORT LOGIC ---
    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile-specific export logic: Check permissions and save to external storage.
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (status.isGranted) {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final file = File('${directory.path}/${DateTime.now().toIso8601String()}.txt');
          await file.writeAsString(fileContent);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied.')));
      }
    } else {
      // Desktop-specific export logic: Use a "Save As" file dialog.
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Your Note',
        fileName: '${DateTime.now().toIso8601String()}.txt',
      );
      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(fileContent);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder textBorder = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(4)), borderSide: BorderSide(width: 1, color: Colors.black54));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note', style: TextStyle(color: Colors.white24)),
        actions: [
          IconButton(icon: const Icon(Icons.sd_storage_outlined), onPressed: _exportNote, tooltip: 'Export Note'),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveNote, color: Colors.yellow),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(2.0),
        child: TextField(controller: _controller, maxLines: null, decoration: InputDecoration(hintText: 'Enter your note', fillColor: Colors.black54, enabledBorder: textBorder, focusedBorder: textBorder), keyboardAppearance: Brightness.dark, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}

// --- EXPORT NOTE DIALOG WIDGET ---

class ExportNoteDialog extends StatefulWidget {
  @override
  _ExportNoteDialogState createState() => _ExportNoteDialogState();
}

class _ExportNoteDialogState extends State<ExportNoteDialog> {
  bool _encrypt = true;
  bool _rememberPassword = false;
  bool _passwordVisible = false;
  final _passwordController = TextEditingController();
  final _sessionManager = SessionManager();

  @override
  void initState() {
    super.initState();
    // Pre-fill password from session if it exists.
    if (_sessionManager.sessionPassword != null) {
      _passwordController.text = _sessionManager.sessionPassword!;
      _rememberPassword = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Options'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('Encrypt with password'),
              value: _encrypt,
              onChanged: (value) => setState(() => _encrypt = value!),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_encrypt) ...[
              TextFormField(
                controller: _passwordController,
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                  ),
                ),
              ),
              CheckboxListTile(
                title: const Text('Remember password for session'),
                value: _rememberPassword,
                onChanged: (value) => setState(() => _rememberPassword = value!),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            // Update or clear the session password based on the checkbox.
            if (_rememberPassword) {
              _sessionManager.sessionPassword = _passwordController.text;
            } else {
              _sessionManager.sessionPassword = null;
            }
            Navigator.of(context).pop({
              'encrypt': _encrypt,
              'password': _passwordController.text,
            });
          },
          child: const Text('Export'),
        ),
      ],
    );
  }
}