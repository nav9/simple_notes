// main.dart
//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html
//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html and https://www.fluttericon.com/
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for clipboard
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as p;
import 'session_manager.dart';

// --- SERVICES (Encryption) ---
class EncryptionService {
  // Fixed IV (for simplicity in this example; see comments in original)
  static final iv = encrypt.IV.fromBase64('AAAAAAAAAAAAAAAAAAAAAA==');

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
      return null;
    }
  }
}

// --- APP INITIALIZATION ---
Future<void> main() async {
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
        floatingActionButtonTheme:
        const FloatingActionButtonThemeData(backgroundColor: Colors.blueGrey),
        textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white70),
            labelLarge: TextStyle(color: Colors.white)),
        inputDecorationTheme: InputDecorationTheme(
            filled: true, fillColor: Colors.grey[800], border: OutlineInputBorder(), labelStyle: TextStyle(color: Colors.white)),
        listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white),
      ),
      themeMode: ThemeMode.dark,
      home: NotesListScreen(),
    );
  }
}

// --- NOTES LIST SCREEN ---
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

  Future<void> _encryptAllDecryptedNotes() async {
    final sessionManager = SessionManager();
    final notes = Hive.box<Map>('notesBox');

    if (_decryptedNotesCache.isEmpty) return;

    // For each decrypted note in session cache use stored password for that key
    for (final entry in _decryptedNotesCache.entries.toList()) {
      final key = entry.key;
      final plainText = entry.value;
      final pw = sessionManager.getNotePassword(key);
      if (pw == null || pw.isEmpty) {
        // If any note lacks password, show message and skip it.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Missing password for a note — skipping some notes.')));
        continue;
      }
      final encryptedText = EncryptionService.encryptText(plainText, pw);
      final oldData = notes.get(key);
      final updated = {
        'content': encryptedText,
        'isEncrypted': true,
        'filename': oldData?['filename'] ?? 'Encrypted Note'
      };
      await notes.put(key, updated);
      _decryptedNotesCache.remove(key);
      sessionManager.clearNotePassword(key); // remove pw from memory after re-encryption
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All decrypted notes have been re-encrypted.')));
    }
  }

  Future<void> _exportAllNotes() async {
    final sessionManager = SessionManager();
    final notes = Hive.box<Map>('notesBox');

    // Ensure export path exists (use session default or application documents)
    String exportDir = sessionManager.defaultExportPath ?? (await getApplicationDocumentsDirectory()).path;
    // On mobile check storage permission
    bool isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (!isDesktop) {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied.')));
        return;
      }
    }

    // First re-encrypt any decrypted notes (using stored passwords)
    for (final entry in _decryptedNotesCache.entries.toList()) {
      final key = entry.key;
      final plainText = entry.value;
      final pw = sessionManager.getNotePassword(key);
      if (pw == null || pw.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing password for some notes. Export skipped for them.')));
        continue;
      }
      final encryptedText = EncryptionService.encryptText(plainText, pw);
      final oldData = notes.get(key);
      final updated = {
        'content': encryptedText,
        'isEncrypted': true,
        'filename': oldData?['filename'] ?? 'Encrypted Note'
      };
      await notes.put(key, updated);
      _decryptedNotesCache.remove(key);
      sessionManager.clearNotePassword(key);
    }

    // Now export each note to exportDir
    Directory dir = Directory(exportDir);
    await dir.create(recursive: true);

    for (int i = 0; i < notes.length; i++) {
      final data = notes.getAt(i)!;
      final filename = data['filename'] ?? 'note_${i + 1}.txt';
      final fullpath = p.join(exportDir, filename);
      try {
        final f = File(fullpath);
        await f.writeAsString(data['content']);
      } catch (e) {
        // skip problematic ones
      }
    }

    // remember last export path
    sessionManager.lastExportPath = exportDir;

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All notes exported.')));
    }
  }

  void _deleteNoteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete confirmation'),
        content: const Text('This will delete the note from the app. Exported files will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('No')),
          TextButton(
            onPressed: () async {
              final key = notesBox.keyAt(index);
              await notesBox.deleteAt(index);
              _decryptedNotesCache.remove(key);
              SessionManager().clearNotePassword(key);
              if (mounted) setState(() {});
              if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
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
          final newNote = {
            'content': content,
            'isEncrypted': isEncrypted,
            'filename': p.basename(file.path!)
          };
          await notesBox.add(newNote);
        }
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleEncryptedNoteTap(int index, Map noteData) async {
    // Ask for password and decrypt, then store decrypted text in cache and store password in session manager
    final password = await _showPasswordDialog(context, "Enter password for '${noteData['filename']}'", false);
    if (password != null && password.isNotEmpty) {
      final decryptedContent = EncryptionService.decryptText(noteData['content'], password);
      if (decryptedContent != null) {
        final key = notesBox.keyAt(index);
        if (mounted) {
          _decryptedNotesCache[key] = decryptedContent;
          SessionManager().storeNotePassword(key, password);
          setState(() {});
        }
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
        actions: [
          // Encrypt all decrypted notes — only visible when decrypted cache not empty
          if (_decryptedNotesCache.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.lock),
              tooltip: 'Encrypt all decrypted notes',
              onPressed: _encryptAllDecryptedNotes,
            ),
          // Export all
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export all notes',
            onPressed: _exportAllNotes,
          ),
          // Import
          IconButton(
              icon: const Icon(Icons.present_to_all),
              tooltip: 'Import Note(s)',
              onPressed: _importNotes),
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
                      // pass the key to EditNoteScreen so we can manage per-note session passwords
                      Navigator.push(context, MaterialPageRoute(builder: (_) => EditNoteScreen(index: index, noteKey: key, note: content)))
                          .then((_) {
                        // After returning, refresh state (in case edits changed encryption)
                        if (mounted) setState(() {});
                      });
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
          onPressed: () {
            // new note: will not have a key yet; after saving it will be put into Hive
            Navigator.push(context, MaterialPageRoute(builder: (_) => EditNoteScreen())).then((_) {
              if (mounted) setState(() {});
            });
          }),
    );
  }
}

// --- EDIT NOTE SCREEN ---
class EditNoteScreen extends StatefulWidget {
  final int? index; // null for new note
  final dynamic? noteKey; // Hive key for existing notes
  final String? note; // content (could be encrypted or decrypted depending on context)
  EditNoteScreen({this.index, this.noteKey, this.note});
  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false; // track focus
  TextSelection? _lastSelection; // remember last selection even if focus changes
  bool _isReadOnlyEncrypted = false; // when editor shows encrypted content in read-only state

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.note ?? '');
    // Determine read-only encrypted state: if the content begins with [ENCRYPTED] and there's no decrypted session cache for this key
    final isEncryptedContent = (_controller.text.startsWith('[ENCRYPTED]'));
    final sessionPw = SessionManager().getNotePassword(widget.noteKey);
    if (isEncryptedContent && sessionPw == null) {
      // Show as read-only encrypted until user decrypts
      _isReadOnlyEncrypted = true;
    } else {
      _isReadOnlyEncrypted = false;
    }

    // Auto-focus new notes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.note == null || widget.note!.isEmpty) {
        _focusNode.requestFocus();
      }
    });

    // track focus
    _focusNode.addListener(() {
      setState(() {
        _isEditing = _focusNode.hasFocus;
      });
    });

    // track selection/ cursor position
    _controller.addListener(() {
      final sel = _controller.selection;
      if (sel.isValid) {
        _lastSelection = sel;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _decryptInEditor() async {
    // Ask for password, decrypt and store session password
    final password = await _showPasswordDialog(context, "Enter password to decrypt note", false);
    if (password != null && password.isNotEmpty) {
      final decrypted = EncryptionService.decryptText(_controller.text, password);
      if (decrypted != null) {
        // store password in session per-note
        if (widget.noteKey != null) SessionManager().storeNotePassword(widget.noteKey, password);
        setState(() {
          _controller.text = decrypted;
          _isReadOnlyEncrypted = false;
        });
        // keep focus in editor
        Future.delayed(const Duration(milliseconds: 50), () {
          _focusNode.requestFocus();
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note decrypted successfully!')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')));
      }
    }
  }

  Future<void> _encryptInEditor() async {
    // If we already have a stored password for this note, use it; otherwise ask for a new password
    final session = SessionManager();
    String? pw = widget.noteKey != null ? session.getNotePassword(widget.noteKey) : null;
    if (pw == null || pw.isEmpty) {
      final p = await _showPasswordDialog(context, "Set password to encrypt note", true);
      if (p == null || p.isEmpty) {
        // user cancelled
        return;
      }
      pw = p;
      if (widget.noteKey != null) session.storeNotePassword(widget.noteKey, pw);
    }
    final encryptedText = EncryptionService.encryptText(_controller.text, pw);
    setState(() {
      _controller.text = encryptedText;
      _isReadOnlyEncrypted = true;
    });
    // update Hive (if it's an existing note)
    final notesBox = Hive.box<Map>('notesBox');
    final newNoteData = {
      'content': encryptedText,
      'isEncrypted': true,
      'filename': (widget.index != null) ? (notesBox.getAt(widget.index!)?['filename'] ?? 'Encrypted Note') : 'Encrypted Note'
    };
    if (widget.index != null) {
      await notesBox.putAt(widget.index!, newNoteData);
    } else {
      // creating a new encrypted note — put at front
      final List<Map> tempList = [newNoteData];
      tempList.addAll(notesBox.values);
      await notesBox.clear();
      await notesBox.addAll(tempList);
    }

    // Keep password in session (already stored) — do not write to disk
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note encrypted successfully!')));
    }
  }

  void _saveNote() {
    final notesBox = Hive.box<Map>('notesBox');
    final content = _controller.text;
    final isEncrypted = content.startsWith("[ENCRYPTED]");
    final newNote = {
      'content': content,
      'isEncrypted': isEncrypted,
      'filename': isEncrypted ? 'Encrypted Note' : 'Internal Note'
    };
    if (widget.index != null) {
      notesBox.putAt(widget.index!, newNote);
    } else {
      final List<Map> tempList = [newNote];
      tempList.addAll(notesBox.values);
      notesBox.clear().then((_) => notesBox.addAll(tempList));
    }
    Navigator.pop(context);
  }

  // insert current time at remembered cursor position and keep focus
  void _insertCurrentTime() {
    if (!_isEditing && !_focusNode.hasFocus) {
      // even if the focus left, allow insertion at last known selection
      // but only if last selection exists
      if (_lastSelection == null) return;
    }
    final now = DateTime.now();
    final formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ";

    final sel = _lastSelection ?? _controller.selection;
    if (sel == null || !sel.isValid) {
      // append at end
      final newText = _controller.text + formattedTime;
      final newCursor = newText.length;
      setState(() {
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(offset: newCursor);
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        _focusNode.requestFocus();
      });
      return;
    }

    final start = sel.start;
    final end = sel.end;
    final text = _controller.text;
    final newText = text.replaceRange(start, end, formattedTime);
    final newCursorPos = start + formattedTime.length;

    setState(() {
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: newCursorPos);
      _lastSelection = _controller.selection;
    });

    // Ensure focus returns to editor and cursor positioned properly
    Future.delayed(const Duration(milliseconds: 50), () {
      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(offset: newCursorPos);
      _lastSelection = _controller.selection;
      if (mounted) setState(() {
        _isEditing = _focusNode.hasFocus;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder textBorder = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(4)), borderSide: BorderSide(width: 1, color: Colors.black54));
    final showDecryptGreen = _isReadOnlyEncrypted;

    return WillPopScope(
      onWillPop: () async {
        if (_controller.text.trim().isNotEmpty && (widget.note == null || _controller.text != widget.note)) {
          final shouldSave = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Save changes?'),
              content: const Text('Do you want to save this note before leaving?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Discard')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
              ],
            ),
          );
          if (shouldSave == true) _saveNote();
          return shouldSave != null;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          // Insert time on left (leading)
          leading: IconButton(
            icon: const Icon(Icons.access_time),
            tooltip: 'Insert Current Time',
            onPressed: (_isEditing || _lastSelection != null) ? _insertCurrentTime : null,
            color: (_isEditing || _lastSelection != null) ? Colors.white : Colors.white24,
          ),
          title: const Text('Edit Note', style: TextStyle(color: Colors.white24)),
          actions: [
            // Copy button always available
            IconButton(icon: const Icon(Icons.copy), onPressed: _copyToClipboard, tooltip: 'Copy'),

            // If the note is encrypted and read-only, show green decrypt button
            IconButton(
              icon: const Icon(Icons.enhanced_encryption),
              onPressed: _isReadOnlyEncrypted ? _decryptInEditor : _encryptInEditor,
              tooltip: _isReadOnlyEncrypted ? 'Decrypt Note' : 'Encrypt Note',
              color: _isReadOnlyEncrypted ? Colors.green : null,
            ),

            IconButton(icon: const Icon(Icons.system_update_alt), onPressed: _exportNote, tooltip: 'Export Note'),
            IconButton(icon: const Icon(Icons.save), onPressed: _saveNote, color: Colors.yellow),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            readOnly: _isReadOnlyEncrypted,
            decoration: InputDecoration(hintText: 'Enter your note', fillColor: Colors.black54, enabledBorder: textBorder, focusedBorder: textBorder),
            keyboardAppearance: Brightness.dark,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Future<void> _exportNote() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportNoteDialog(noteContent: _controller.text),
    );
    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exported successfully!'), duration: Duration(seconds: 2)));
    }
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

// Export dialog (unchanged logic except uses session defaults)
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
      final finalPath = p.join(_currentPath, filename);

      if (!_isDesktop) {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        if (!status.isGranted) throw "Storage permission was denied.";
      }

      final file = File(finalPath);
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
