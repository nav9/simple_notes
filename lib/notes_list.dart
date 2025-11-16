// lib/notes_list.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'session_manager.dart';
import 'encryption_service.dart';
import 'edit_note.dart';
import 'help.dart';
import 'trash.dart';
import 'package:file_picker/file_picker.dart';

class NotesListScreen extends StatefulWidget {
  @override
  _NotesListScreenState createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  late Box<Map> notesBox;
  final Map<dynamic, String> _decryptedNotesCache = {}; // key => plaintext
  final SessionManager _session = SessionManager();

  @override
  void initState() {
    super.initState();
    notesBox = Hive.box<Map>('notesBox');
  }

  Future<void> _encryptAllDecryptedNotes() async {
    try {
      if (_decryptedNotesCache.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No decrypted notes in session to encrypt.')));
        _session.clearAllNotePasswords();
        return;
      }
      for (final entry in _decryptedNotesCache.entries.toList()) {
        final key = entry.key;
        final plain = entry.value;
        final pw = _session.getNotePassword(key);
        if (pw == null || pw.isEmpty) continue;
        final enc = EncryptionService.encryptText(plain, pw);
        final old = notesBox.get(key);
        final updated = {
          'content': enc,
          'isEncrypted': true,
          'title': old?['title'] ?? null,
          'isTrashed': old?['isTrashed'] ?? false
        };
        await notesBox.put(key, updated);
        _decryptedNotesCache.remove(key);
        _session.clearNotePassword(key);
      }
      _session.clearAllNotePasswords();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encrypted session-decrypted notes and cleared passwords.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to encrypt all: $e')));
    }
  }

  void _moveNoteToTrash(int index) async {
    try {
      final key = notesBox.keyAt(index);
      final note = notesBox.getAt(index)!;
      final updated = Map<String, dynamic>.from(note);
      updated['isTrashed'] = true;
      await notesBox.put(key, updated);
      _decryptedNotesCache.remove(key);
      _session.clearNotePassword(key);

      final snackBar = SnackBar(
        content: const Text('Note moved to Trash. You can restore it from the menu.'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to move to trash: $e')));
    }
  }

  Future<void> _importNotes() async {
    try {
      FilePickerResult? res = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['txt']);
      if (res == null) return;
      for (var file in res.files) {
        if (file.path == null) continue;
        final content = await File(file.path!).readAsString();
        final isEncrypted = content.startsWith('[ENCRYPTED]');
        final titleGuess = p.basenameWithoutExtension(file.path!);
        final newNote = {
          'content': content,
          'isEncrypted': isEncrypted,
          'title': titleGuess.isEmpty ? null : titleGuess,
          'isTrashed': false,
        };
        await notesBox.add(newNote);
      }
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _exportAll() async {
    try {
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
      final exportDir = Directory(p.join(dir.path, 'simple_notes_export'));
      await exportDir.create(recursive: true);

      int ordinal = 1;
      for (int i = 0; i < notesBox.length; i++) {
        final n = notesBox.getAt(i)!;
        final title = (n['title'] as String?)?.trim();
        String filename;
        if (title != null && title.isNotEmpty) {
          filename = title;
        } else {
          filename = 'note_${ordinal++}';
        }
        if (!filename.toLowerCase().endsWith('.txt')) filename = '$filename.txt';
        final path = p.join(exportDir.path, filename);
        try {
          await File(path).writeAsString(n['content']);
        } catch (e) {
          // ignore single-file errors
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported notes to ${exportDir.path}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Widget _buildTileForNote(int index) {
    final note = notesBox.getAt(index)!;
    final key = notesBox.keyAt(index);
    final isTrashed = note['isTrashed'] ?? false;
    if (isTrashed) return SizedBox.shrink();

    final isEncrypted = note['isEncrypted'] ?? false;
    final title = (note['title'] as String?)?.trim();
    String displayTitle;
    String displaySubtitle = '';

    if (title != null && title.isNotEmpty) {
      displayTitle = title;
      if (!isEncrypted) {
        final content = note['content'] as String;
        displaySubtitle = _singleLineSnippet(content);
      } else {
        // If decrypted in session show decrypted state
        final sessionPw = _session.getNotePassword(key);
        if (sessionPw != null && sessionPw.isNotEmpty) {
          displaySubtitle = 'Decrypted';
        } else {
          displaySubtitle = '🔒 Encrypted';
        }
      }
    } else {
      if (isEncrypted) {
        displayTitle = '🔒 Encrypted: ${note['filename'] ?? 'Encrypted Note'}';
        displaySubtitle = '';
      } else {
        final content = note['content'] as String;
        displayTitle = _singleLineSnippet(content);
      }
    }

    final sessionPw = _session.getNotePassword(key);
    final isDecryptedInSession = sessionPw != null && sessionPw.isNotEmpty;

    return Card(
      child: ListTile(
        leading: IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          onPressed: () => _moveNoteToTrash(index),
        ),
        title: Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: displaySubtitle.isNotEmpty ? Text(displaySubtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
        trailing: isEncrypted
            ? Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isDecryptedInSession ? Icons.lock_open : Icons.lock),
          if (isDecryptedInSession) const SizedBox(width: 6),
          if (isDecryptedInSession) const Text('Decrypted', style: TextStyle(color: Colors.greenAccent))
        ])
            : null,
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
                Navigator.push(context, MaterialPageRoute(builder: (_) => HelpScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Trash'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => TrashScreen()));
              },
            ),
          ],
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: notesBox.listenable(),
        builder: (context, Box<Map> box, _) {
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
