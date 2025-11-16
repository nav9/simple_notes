// main.dart
//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html
//Flutter icons: https://api.flutter.dev/flutter/material/Icons-class.html and https://www.fluttericon.com/
// lib/main.dart
// Single-file implementation (giant file) using Hive + setState + Navigator
// Keep your session_manager.dart as provided (in lib/session_manager.dart)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path/path.dart' as p;
import 'session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDir.path);
  await Hive.openBox<Map>('notesBox');
  runApp(SimpleNotesApp());
}

class EncryptionService {
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

class SimpleNotesApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Notes',
      theme: ThemeData.dark(),
      home: NotesListScreen(),
    );
  }
}

class NotesListScreen extends StatefulWidget {
  @override
  _NotesListScreenState createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  late Box<Map> notesBox;
  final Map<dynamic, String> _decryptedNotesCache = {}; // per-note plaintext cache
  final SessionManager _session = SessionManager();

  @override
  void initState() {
    super.initState();
    notesBox = Hive.box<Map>('notesBox');
  }

  // Encrypt all notes that we currently have decrypted in memory (use stored per-note passwords).
  Future<void> _encryptAllDecryptedNotes() async {
    if (_decryptedNotesCache.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No decrypted notes in session to encrypt.')));
      // still clear all stored passwords per requirement
      _session.clearAllNotePasswords();
      return;
    }

    for (final entry in _decryptedNotesCache.entries.toList()) {
      final key = entry.key;
      final plainText = entry.value;
      final pw = _session.getNotePassword(key);
      if (pw == null || pw.isEmpty) {
        // skip if no pw for this note
        continue;
      }
      final encryptedText = EncryptionService.encryptText(plainText, pw);
      final old = notesBox.get(key);
      final updated = {
        'content': encryptedText,
        'isEncrypted': true,
        'title': old?['title'] ?? null,
        'isTrashed': old?['isTrashed'] ?? false
      };
      await notesBox.put(key, updated);
      _decryptedNotesCache.remove(key);
      // clear the per-note password (require re-entry later)
      _session.clearNotePassword(key);
    }

    // clear all passwords for safety (require re-entry)
    _session.clearAllNotePasswords();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All session-decrypted notes re-encrypted; session passwords cleared.')));
    }
  }

  // Move a note to trash (no confirmation) and show undo snackbar at top
  void _moveNoteToTrash(int index) async {
    final key = notesBox.keyAt(index);
    final note = notesBox.getAt(index)!;
    final updated = Map<String, dynamic>.from(note);
    updated['isTrashed'] = true;
    await notesBox.put(key, updated);
    // remove from decrypted cache & clear per-note password
    _decryptedNotesCache.remove(key);
    _session.clearNotePassword(key);

    // Show floating top-positioned snackbar for 3 seconds with UNDO
    final snackBar = SnackBar(
      content: const Text('Note moved to Trash. You can restore it from the menu.'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0), // near top
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          final restored = Map<String, dynamic>.from(await notesBox.get(key) as Map);
          restored['isTrashed'] = false;
          await notesBox.put(key, restored);
          if (mounted) setState(() {});
        },
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);

    if (mounted) setState(() {});
  }

  // Import notes (txt files)
  Future<void> _importNotes() async {
    FilePickerResult? res = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['txt']);
    if (res != null) {
      for (var file in res.files) {
        if (file.path == null) continue;
        final content = await File(file.path!).readAsString();
        final isEncrypted = content.startsWith('[ENCRYPTED]');
        final newNote = {
          'content': content,
          'isEncrypted': isEncrypted,
          'title': p.basename(file.path!), // default title from filename
          'isTrashed': false,
        };
        await notesBox.add(newNote);
      }
      if (mounted) setState(() {});
    }
  }

  // Export all notes to a folder (re-encrypt decrypted notes first)
  Future<void> _exportAll() async {
    // ensure storage permission for mobile
    bool isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (!isDesktop) {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied.')));
        return;
      }
    }

    // choose export directory (use app documents)
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'simple_notes_export'));
    await exportDir.create(recursive: true);

    for (int i = 0; i < notesBox.length; i++) {
      final n = notesBox.getAt(i)!;
      final filename = (n['title'] != null && (n['title'] as String).trim().isNotEmpty) ? n['title'] : 'note_$i.txt';
      final path = p.join(exportDir.path, filename);
      try {
        await File(path).writeAsString(n['content']);
      } catch (e) {
        // ignore write errors and continue
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported notes to ${exportDir.path}')));
  }

  // Drawer: Help & Trash pages
  void _openHelp() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => HelpScreen()));
  }

  void _openTrash() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TrashScreen()));
  }

  Widget _buildTileForNote(int index) {
    final note = notesBox.getAt(index)!;
    final key = notesBox.keyAt(index);
    final isTrashed = note['isTrashed'] ?? false;
    if (isTrashed) return SizedBox.shrink(); // don't show trashed here

    final isEncrypted = note['isEncrypted'] ?? false;
    final title = (note['title'] as String?)?.trim();
    String displayTitle;
    String displaySubtitle = '';

    if (title != null && title.isNotEmpty) {
      displayTitle = title;
      // subtitle show small snippet if available
      if (!isEncrypted) {
        final content = note['content'] as String;
        displaySubtitle = _singleLineSnippet(content);
      } else {
        displaySubtitle = '🔒 Encrypted';
      }
    } else {
      // if no title, show snippet of content or encrypted placeholder
      if (isEncrypted) {
        displayTitle = '🔒 Encrypted: ${note['filename'] ?? 'Encrypted Note'}';
        displaySubtitle = '';
      } else {
        final content = note['content'] as String;
        displayTitle = _singleLineSnippet(content);
      }
    }

    return Card(
      child: ListTile(
        title: Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: displaySubtitle.isNotEmpty ? Text(displaySubtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
        leading: IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          onPressed: () => _moveNoteToTrash(index),
        ),
        onTap: () {
          final content = note['content'] as String;
          final initialIsEncrypted = (note['isEncrypted'] ?? false) as bool;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditNoteScreen(index: index, noteKey: key, note: content, initialIsEncrypted: initialIsEncrypted)),
          ).then((_) {
            if (mounted) setState(() {});
          });
        },
      ),
    );
  }

  String _singleLineSnippet(String text, {int maxLen = 100}) {
    final single = text.replaceAll('\n', ' ');
    if (single.length <= maxLen) return single;
    return single.substring(0, maxLen) + '...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Notes'),
        actions: [
          IconButton(icon: const Icon(Icons.lock), tooltip: 'Encrypt all decrypted notes', onPressed: _encryptAllDecryptedNotes),
          IconButton(icon: const Icon(Icons.download_outlined), tooltip: 'Export all notes', onPressed: _exportAll),
          IconButton(icon: const Icon(Icons.input), tooltip: 'Import notes', onPressed: _importNotes),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(child: Text('Menu', style: Theme.of(context).textTheme.headlineSmall)),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help'),
              onTap: () {
                Navigator.pop(context);
                _openHelp();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Trash'),
              onTap: () {
                Navigator.pop(context);
                _openTrash();
              },
            ),
          ],
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Map> box, _) {
          // show non-trashed notes only
          final nonTrashIndices = <int>[];
          for (var i = 0; i < box.length; i++) {
            final n = box.getAt(i)!;
            final isTrashed = n['isTrashed'] ?? false;
            if (!isTrashed) nonTrashIndices.add(i);
          }
          if (nonTrashIndices.isEmpty) return const Center(child: Text('No notes. Tap + to create or import one.'));
          return ListView.builder(
            itemCount: nonTrashIndices.length,
            itemBuilder: (context, idx) {
              final i = nonTrashIndices[idx];
              return _buildTileForNote(i);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => EditNoteScreen())).then((_) {
            if (mounted) setState(() {});
          });
        },
      ),
    );
  }
}

// --- EditNoteScreen ---
class EditNoteScreen extends StatefulWidget {
  final int? index; // Hive index (position)
  final dynamic? noteKey; // Hive key
  final String? note; // content (encrypted or plaintext)
  final bool initialIsEncrypted;

  EditNoteScreen({this.index, this.noteKey, this.note, this.initialIsEncrypted = false});

  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isReadOnlyEncrypted = false;
  bool _isEditing = false;
  TextSelection? _lastSelection;
  String? _originalTextSnapshot; // used to detect dirty changes
  String? _originalTitleSnapshot;
  final _notesBox = Hive.box<Map>('notesBox');
  final _session = SessionManager();

  @override
  void initState() {
    super.initState();
    final content = widget.note ?? '';
    _textController.text = content;
    _originalTextSnapshot = content;
    // load title if exists
    if (widget.noteKey != null) {
      final entry = _notesBox.get(widget.noteKey);
      if (entry != null && entry['title'] != null) {
        _titleController.text = entry['title'] as String;
        _originalTitleSnapshot = _titleController.text;
      }
    }

    final isEncryptedContent = content.startsWith('[ENCRYPTED]') || widget.initialIsEncrypted;
    final sessionPw = _session.getNotePassword(widget.noteKey);
    if (isEncryptedContent && (sessionPw == null)) {
      _isReadOnlyEncrypted = true;
    } else if (isEncryptedContent && sessionPw != null) {
      // try to decrypt with stored password
      final dec = EncryptionService.decryptText(content, sessionPw);
      if (dec != null) {
        _textController.text = dec;
        _originalTextSnapshot = dec;
        _isReadOnlyEncrypted = false;
      } else {
        _isReadOnlyEncrypted = true;
      }
    } else {
      _isReadOnlyEncrypted = false;
    }

    _focusNode.addListener(() {
      setState(() {
        _isEditing = _focusNode.hasFocus;
      });
    });

    _textController.addListener(() {
      final sel = _textController.selection;
      if (sel.isValid) _lastSelection = sel;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final currentText = _textController.text;
    final currentTitle = _titleController.text;
    if (_originalTextSnapshot != null && currentText != _originalTextSnapshot) return true;
    if (_originalTitleSnapshot != null && currentTitle != _originalTitleSnapshot) return true;
    // if original snapshots were null and user entered text/title, treat as dirty
    if (_originalTextSnapshot == null && currentText.trim().isNotEmpty) return true;
    if (_originalTitleSnapshot == null && currentTitle.trim().isNotEmpty) return true;
    return false;
  }

  Future<bool> _onWillPop() async {
    if (_isDirty) {
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
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _textController.text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _decryptInEditor() async {
    final password = await _showPasswordDialog(context, "Enter password to decrypt note", false);
    if (password == null || password.isEmpty) return;
    final decrypted = EncryptionService.decryptText(_textController.text, password);
    if (decrypted != null) {
      // store per-note password
      if (widget.noteKey != null) _session.storeNotePassword(widget.noteKey, password);
      else _session.sessionPassword = password;
      setState(() {
        _textController.text = decrypted;
        _originalTextSnapshot = decrypted; // treat this as saved baseline
        _isReadOnlyEncrypted = false;
      });
      // focus editor
      Future.delayed(const Duration(milliseconds: 50), () => _focusNode.requestFocus());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decrypted successfully')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')));
    }
  }

  Future<void> _encryptInEditor() async {
    // get a password: either stored or ask user to set one
    final session = _session;
    String? pw = widget.noteKey != null ? session.getNotePassword(widget.noteKey) : session.sessionPassword;
    if (pw == null || pw.isEmpty) {
      final p = await _showPasswordDialog(context, "Set password to encrypt note", true);
      if (p == null || p.isEmpty) return;
      pw = p;
      if (widget.noteKey != null) session.storeNotePassword(widget.noteKey, pw);
      else session.sessionPassword = pw;
    }

    final encryptedText = EncryptionService.encryptText(_textController.text, pw);

    final newNote = {
      'content': encryptedText,
      'isEncrypted': true,
      'title': (_titleController.text.trim().isEmpty) ? null : _titleController.text.trim(),
      'isTrashed': false,
    };

    if (widget.index != null) {
      await _notesBox.putAt(widget.index!, newNote);
    } else {
      // add to front
      final List<Map> temp = [Map<String, dynamic>.from(newNote)];
      temp.addAll(_notesBox.values.map((e) => Map<String, dynamic>.from(e)));
      await _notesBox.clear();
      await _notesBox.addAll(temp);
    }

    // After encrypting or re-encrypting, clear the password in memory for this note
    if (widget.noteKey != null) _session.clearNotePassword(widget.noteKey);
    else _session.sessionPassword = null;

    setState(() {
      _textController.text = encryptedText;
      _originalTextSnapshot = encryptedText;
      _isReadOnlyEncrypted = true;
    });

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note encrypted. Password cleared from session; re-enter to decrypt later.')));
  }

  Future<void> _saveNote() async {
    final content = _textController.text;
    final titleText = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
    final sessionPw = widget.noteKey != null ? _session.getNotePassword(widget.noteKey) : _session.sessionPassword;
    final shouldEncryptOnDisk = sessionPw != null && sessionPw.isNotEmpty;

    if (shouldEncryptOnDisk) {
      // encrypt content and store encrypted on disk, but keep UI plaintext
      final encryptedText = EncryptionService.encryptText(content, sessionPw!);
      final newNote = {
        'content': encryptedText,
        'isEncrypted': true,
        'title': titleText,
        'isTrashed': false,
      };

      if (widget.index != null) {
        await _notesBox.putAt(widget.index!, newNote);
      } else {
        final List<Map> temp = [Map<String, dynamic>.from(newNote)];
        temp.addAll(_notesBox.values.map((e) => Map<String, dynamic>.from(e)));
        await _notesBox.clear();
        await _notesBox.addAll(temp);
      }

      // keep session password in memory so the UI shows decrypted view
      if (widget.noteKey != null) _session.storeNotePassword(widget.noteKey, sessionPw);
      else _session.sessionPassword = sessionPw;
      // keep _textController as plaintext (user remains seeing plaintext)
      _originalTextSnapshot = content;
    } else {
      // plain save (no encryption)
      final newNote = {
        'content': content,
        'isEncrypted': false,
        'title': titleText,
        'isTrashed': false,
      };
      if (widget.index != null) {
        await _notesBox.putAt(widget.index!, newNote);
      } else {
        final List<Map> temp = [Map<String, dynamic>.from(newNote)];
        temp.addAll(_notesBox.values.map((e) => Map<String, dynamic>.from(e)));
        await _notesBox.clear();
        await _notesBox.addAll(temp);
      }
      _originalTextSnapshot = content;
    }

    _originalTitleSnapshot = titleText;
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }

    // return to previous screen
    Navigator.pop(context);
  }

  Future<void> _insertCurrentTime() async {
    if (_isReadOnlyEncrypted) return;
    if (!_isEditing && _lastSelection == null) return;
    final now = DateTime.now();
    final formatted = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ";
    final sel = _lastSelection ?? _textController.selection;
    if (!sel.isValid) {
      final newText = _textController.text + formatted;
      final newCursor = newText.length;
      setState(() {
        _textController.text = newText;
        _textController.selection = TextSelection.collapsed(offset: newCursor);
        _originalTextSnapshot ??= '';
      });
      Future.delayed(const Duration(milliseconds: 50), () => _focusNode.requestFocus());
      return;
    }
    final start = sel.start;
    final end = sel.end;
    final text = _textController.text;
    final newText = text.replaceRange(start, end, formatted);
    final newPos = start + formatted.length;
    setState(() {
      _textController.text = newText;
      _textController.selection = TextSelection.collapsed(offset: newPos);
    });
    Future.delayed(const Duration(milliseconds: 50), () => _focusNode.requestFocus());
  }

  Future<void> _exportNote() async {
    // export to app documents (or ask user)
    bool isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (!isDesktop) {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied.')));
        return;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final filename = (_titleController.text.trim().isNotEmpty) ? _titleController.text.trim() : 'note_${DateTime.now().millisecondsSinceEpoch}.txt';
    final path = p.join(dir.path, filename);
    try {
      await File(path).writeAsString(_textController.text);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canInsertTime = !_isReadOnlyEncrypted && (_isEditing || _lastSelection != null);
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titleController.text.trim().isNotEmpty ? _titleController.text.trim() : (widget.initialIsEncrypted ? 'Encrypted Note' : 'Edit Note')),
          // default back button will appear
          actions: [
            IconButton(
              icon: const Icon(Icons.access_time),
              tooltip: 'Insert Current Time',
              onPressed: canInsertTime ? _insertCurrentTime : null,
              color: canInsertTime ? Colors.white : Colors.white24,
            ),
            IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy', onPressed: _copyToClipboard),
            IconButton(
              icon: const Icon(Icons.enhanced_encryption),
              tooltip: _isReadOnlyEncrypted ? 'Decrypt Note' : 'Encrypt Note',
              onPressed: _isReadOnlyEncrypted ? _decryptInEditor : _encryptInEditor,
              color: _isReadOnlyEncrypted ? Colors.green : null,
            ),
            IconButton(icon: const Icon(Icons.system_update_alt), tooltip: 'Export note', onPressed: _exportNote),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save',
              onPressed: _isReadOnlyEncrypted ? null : _saveNote,
              color: _isReadOnlyEncrypted ? Colors.white24 : Colors.yellow,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title (optional)', hintText: 'Identifying name (not encrypted)'),
                onChanged: (v) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  readOnly: _isReadOnlyEncrypted,
                  maxLines: null,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter your note'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- TrashScreen ---
class TrashScreen extends StatefulWidget {
  @override
  _TrashScreenState createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Box<Map> _notesBox = Hive.box<Map>('notesBox');
  final Map<dynamic, bool> _selected = {};

  List<int> _trashedIndices() {
    final res = <int>[];
    for (int i = 0; i < _notesBox.length; i++) {
      final n = _notesBox.getAt(i)!;
      final isTrashed = n['isTrashed'] ?? false;
      if (isTrashed) res.add(i);
    }
    return res;
  }

  void _toggleSelect(dynamic key) {
    setState(() {
      _selected[key] = !(_selected[key] ?? false);
      if (_selected[key] == false) _selected.remove(key);
    });
  }

  Future<void> _restoreSelected() async {
    final keys = List<dynamic>.from(_selected.keys);
    for (final k in keys) {
      final n = Map<String, dynamic>.from(await _notesBox.get(k) as Map);
      n['isTrashed'] = false;
      await _notesBox.put(k, n);
      _selected.remove(k);
    }
    if (mounted) setState(() {});
  }

  Future<void> _permanentlyDeleteSelected() async {
    final keys = List<dynamic>.from(_selected.keys);
    // Deleting keys needs care: delete by key
    for (final k in keys) {
      await _notesBox.delete(k);
      _selected.remove(k);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trashed = _trashedIndices();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          TextButton(
            onPressed: _selected.isNotEmpty ? _restoreSelected : null,
            child: const Text('Restore', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: _selected.isNotEmpty ? _permanentlyDeleteSelected : null,
            child: const Text('Delete permanently', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: _notesBox.listenable(),
        builder: (context, Box<Map> box, _) {
          final list = _trashedIndices();
          if (list.isEmpty) return const Center(child: Text('Trash is empty.'));
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, idx) {
              final i = list[idx];
              final note = box.getAt(i)!;
              final key = box.keyAt(i);
              final title = (note['title'] as String?) ?? '';
              final snippet = (note['isEncrypted'] ?? false) ? '🔒 Encrypted' : (note['content'] as String).split('\n').first;
              final checked = _selected.containsKey(key);
              return CheckboxListTile(
                value: checked,
                onChanged: (_) => _toggleSelect(key),
                title: Text(title.isNotEmpty ? title : snippet, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            },
          );
        },
      ),
    );
  }
}

// --- HelpScreen ---
class HelpScreen extends StatelessWidget {
  final List<Map<String, String>> items = [
    {'icon': 'add', 'explain': 'Add a new note'},
    {'icon': 'delete', 'explain': 'Delete (moves to Trash; use Undo to restore). No confirmation.'},
    {'icon': 'lock', 'explain': 'Encrypt all decrypted notes (clears session passwords)'},
    {'icon': 'download_outlined', 'explain': 'Export all notes to app documents folder'},
    {'icon': 'present_to_all', 'explain': 'Import note(s) from .txt files'},
    {'icon': 'access_time', 'explain': 'Insert current time into note (enabled when editing)'},
    {'icon': 'copy', 'explain': 'Copy note contents to clipboard'},
    {'icon': 'enhanced_encryption', 'explain': 'Encrypt / Decrypt the current note. Encrypted content remains unreadable unless decrypted with password.'},
    {'icon': 'system_update_alt', 'explain': 'Export current note to a file'},
    {'icon': 'save', 'explain': 'Save note (when editing). If a password is stored in session, saving will persist encrypted content on disk but keep UI plaintext until re-encrypted or app restart.'},
  ];

  IconData _iconFromName(String name) {
    switch (name) {
      case 'add':
        return Icons.add;
      case 'delete':
        return Icons.delete;
      case 'lock':
        return Icons.lock;
      case 'download_outlined':
        return Icons.download_outlined;
      case 'present_to_all':
        return Icons.present_to_all;
      case 'access_time':
        return Icons.access_time;
      case 'copy':
        return Icons.copy;
      case 'enhanced_encryption':
        return Icons.enhanced_encryption;
      case 'system_update_alt':
        return Icons.system_update_alt;
      case 'save':
        return Icons.save;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return ListTile(
            leading: Icon(_iconFromName(it['icon']!)),
            title: Text(it['icon']!),
            subtitle: Text(it['explain']!),
          );
        },
      ),
    );
  }
}

// --- Utility password dialog ---
Future<String?> _showPasswordDialog(BuildContext context, String title, bool allowPrefill) {
  final controller = TextEditingController();
  final session = SessionManager();
  if (allowPrefill && session.sessionPassword != null) controller.text = session.sessionPassword!;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'Password'),
        obscureText: true,
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
      ],
    ),
  );
}
