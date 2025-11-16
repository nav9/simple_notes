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

  // selection state
  final Set<dynamic> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    notesBox = Hive.box<Map>('notesBox');
  }

  // Encrypt all notes that we currently have decrypted in memory (use stored per-note passwords).
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

  // Move selected notes to trash
  Future<void> _moveSelectedToTrash() async {
    try {
      for (final key in List<dynamic>.from(_selectedKeys)) {
        // find index of key
        final idx = _indexOfKey(key);
        if (idx == -1) continue;
        final note = notesBox.get(key)!;
        final updated = Map<String, dynamic>.from(note);
        updated['isTrashed'] = true;
        await notesBox.put(key, updated);
        _decryptedNotesCache.remove(key);
        _session.clearNotePassword(key);
      }
      // show top snackbar with UNDO for the last moved note (simpler)
      final snackBar = SnackBar(
        content: const Text('Selected notes moved to Trash.'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            for (final key in List<dynamic>.from(_selectedKeys)) {
              final n = Map<String, dynamic>.from(await notesBox.get(key) as Map);
              n['isTrashed'] = false;
              await notesBox.put(key, n);
            }
            if (mounted) setState(() {});
          },
        ),
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(snackBar);

      _selectedKeys.clear();
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to move to trash: $e')));
    }
  }

  // Toggle selection for a key
  void _toggleSelection(dynamic key) {
    setState(() {
      if (_selectedKeys.contains(key))
        _selectedKeys.remove(key);
      else
        _selectedKeys.add(key);
    });
  }

  void _selectAll() {
    setState(() {
      _selectedKeys.clear();
      for (int i = 0; i < notesBox.length; i++) {
        final n = notesBox.getAt(i)!;
        if (!(n['isTrashed'] ?? false)) _selectedKeys.add(notesBox.keyAt(i));
      }
    });
  }

  void _selectNone() {
    setState(() {
      _selectedKeys.clear();
    });
  }

  // Duplicate selected notes
  Future<void> _duplicateSelected() async {
    try {
      // We'll duplicate in the order of keys (to keep predictable).
      final keysToDup = List<dynamic>.from(_selectedKeys);
      for (final key in keysToDup) {
        final note = await notesBox.get(key) as Map?;
        if (note == null) continue;
        final title = (note['title'] as String?) ?? '';
        final isEncrypted = (note['isEncrypted'] ?? false) as bool;

        // figure out next suffix
        final baseTitle = title.isNotEmpty ? title : 'note';
        final nextTitle = _nextCopyTitle(baseTitle);

        if (isEncrypted) {
          // Duplicate encrypted — keep encryption properties and content
          final newNote = {
            'content': note['content'],
            'isEncrypted': true,
            'title': nextTitle,
            'isTrashed': false,
          };
          // add to front
          final List<Map> tempList = [Map<String, dynamic>.from(newNote)];
          tempList.addAll(notesBox.values.map((e) => Map<String, dynamic>.from(e)));
          await notesBox.clear();
          await notesBox.addAll(tempList);

          // No session password for duplicate unless we can derive one (we don't)
        } else {
          // If the original is decrypted in session, duplicate as plaintext (not encrypted)
          final sessionPw = _session.getNotePassword(key);
          String? plain;
          if (sessionPw != null && sessionPw.isNotEmpty) {
            // original may be encrypted on disk but decrypted in session;
            // attempt to decrypt original content with pw; if fails we'll fallback to stored content
            final tryDec = EncryptionService.decryptText(note['content'] as String, sessionPw);
            if (tryDec != null) plain = tryDec;
            else plain = note['content'] as String;
          } else {
            // original is not decrypted-in-session — copy its visible content (which is plaintext)
            plain = note['content'] as String;
          }

          final newNote = {
            'content': plain,
            'isEncrypted': false,
            'title': nextTitle,
            'isTrashed': false,
          };
          final List<Map> tempList = [Map<String, dynamic>.from(newNote)];
          tempList.addAll(notesBox.values.map((e) => Map<String, dynamic>.from(e)));
          await notesBox.clear();
          await notesBox.addAll(tempList);
        }
      } // end for

      // After duplication, clear selection
      _selectedKeys.clear();
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicated selected notes')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Duplicate failed: $e')));
    }
  }

  // Helper: find next available copy title e.g., "Name_copy1", "_copy2", etc.
  String _nextCopyTitle(String base) {
    final existingTitles = <String>{};
    for (int i = 0; i < notesBox.length; i++) {
      final n = notesBox.getAt(i)!;
      final t = (n['title'] as String?) ?? '';
      if (t.isNotEmpty) existingTitles.add(t);
    }

    // if base_copy1 not present, use it
    int idx = 1;
    String candidate = '${base}_copy$idx';
    while (existingTitles.contains(candidate)) {
      idx++;
      candidate = '${base}_copy$idx';
    }
    return candidate;
  }

  // Import notes (txt files) — title used as filename base (without extension)
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

  // Export selected notes if any selected, else export all notes to folder; uses title as filename if present, otherwise unique ordinal
  Future<void> _exportAllOrSelected() async {
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

      final keysToExport = _selectedKeys.isNotEmpty ? List<dynamic>.from(_selectedKeys) : List<dynamic>.from(notesBox.keys);

      int ordinal = 1;
      for (final key in keysToExport) {
        try {
          final n = await notesBox.get(key) as Map?;
          if (n == null) continue;
          if (n['isTrashed'] ?? false) continue;
          final title = (n['title'] as String?)?.trim();
          String filename;
          if (title != null && title.isNotEmpty) {
            filename = title;
          } else {
            filename = 'note_${ordinal++}';
          }
          if (!filename.toLowerCase().endsWith('.txt')) filename = '$filename.txt';
          final path = p.join(exportDir.path, filename);
          await File(path).writeAsString(n['content']);
        } catch (e) {
          // ignore per-file errors
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported notes to ${exportDir.path}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  // Build tile
  Widget _tileForIndex(int index) {
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
        final sessionPw = _session.getNotePassword(key);
        if (sessionPw != null && sessionPw.isNotEmpty) displaySubtitle = 'Decrypted';
        else displaySubtitle = '🔒 Encrypted';
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

    return ListTile(
      key: ValueKey('note_$index'),
      leading: Checkbox(
        value: _selectedKeys.contains(key),
        onChanged: (_) => _toggleSelection(key),
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
    );
  }

  String _singleLineSnippet(String text, {int maxLen = 100}) {
    final single = text.replaceAll('\n', ' ');
    if (single.length <= maxLen) return single;
    return single.substring(0, maxLen) + '...';
  }

  int _indexOfKey(dynamic key) {
    for (int i = 0; i < notesBox.length; i++) {
      if (notesBox.keyAt(i) == key) return i;
    }
    return -1;
  }

  // Reorder handler: preserves session passwords by moving the parallel list
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    try {
      // Prepare lists
      final items = <Map<String, dynamic>>[];
      final pwList = <String?>[];
      for (int i = 0; i < notesBox.length; i++) {
        final n = Map<String, dynamic>.from(notesBox.getAt(i)!);
        items.add(n);
        final k = notesBox.keyAt(i);
        pwList.add(_session.getNotePassword(k));
      }

      // perform list reordering
      if (newIndex > oldIndex) newIndex -= 1;
      final movedItem = items.removeAt(oldIndex);
      final movedPw = pwList.removeAt(oldIndex);
      items.insert(newIndex, movedItem);
      pwList.insert(newIndex, movedPw);

      // write back (clear + addAll)
      await notesBox.clear();
      await notesBox.addAll(items);

      // reassign session passwords to new keys by index alignment
      for (int i = 0; i < notesBox.length; i++) {
        final k = notesBox.keyAt(i);
        final pw = pwList[i];
        if (pw != null && pw.isNotEmpty)
          _session.storeNotePassword(k, pw);
        else
          _session.clearNotePassword(k);
      }

      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Notes'),
        actions: [
          // Always-visible buttons restored: Encrypt All, Export, Import
          IconButton(icon: const Icon(Icons.lock), tooltip: 'Encrypt all decrypted notes', onPressed: _encryptAllDecryptedNotes),
          IconButton(icon: const Icon(Icons.download_outlined), tooltip: 'Export notes', onPressed: _exportAllOrSelected),
          IconButton(icon: const Icon(Icons.input), tooltip: 'Import notes', onPressed: _importNotes),
          // When some selection exists show duplicate and trash actions and quick select buttons
          if (_selectedKeys.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all',
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Select none',
              onPressed: _selectNone,
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Duplicate selected',
              onPressed: _duplicateSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Move selected to Trash',
              onPressed: _moveSelectedToTrash,
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (s) {
              switch (s) {
                case 'select_all':
                  _selectAll();
                  break;
                case 'select_none':
                  _selectNone();
                  break;
                case 'encrypt_all':
                  _encryptAllDecryptedNotes();
                  break;
                case 'export_all':
                  _exportAllOrSelected();
                  break;
                case 'import':
                  _importNotes();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'select_all', child: Text('Select all')),
              const PopupMenuItem(value: 'select_none', child: Text('Select none')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'encrypt_all', child: Text('Encrypt all decrypted notes')),
              const PopupMenuItem(value: 'export_all', child: Text('Export notes')),
              const PopupMenuItem(value: 'import', child: Text('Import notes')),
            ],
          ),
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
          // build list of indices for non-trashed items
          final visibleIndices = <int>[];
          for (var i = 0; i < box.length; i++) {
            final n = box.getAt(i)!;
            final isTrashed = n['isTrashed'] ?? false;
            if (!isTrashed) visibleIndices.add(i);
          }

          if (visibleIndices.isEmpty) return const Center(child: Text('No notes. Tap + to create or import one.'));

          // use ReorderableListView; we need a mapping of visibleIndices -> display widgets
          return ReorderableListView.builder(
            onReorder: (oldIdx, newIdx) {
              // Map visible index positions (0..N-1) to actual box indices
              final actualOld = visibleIndices[oldIdx];
              int actualNew;
              if (newIdx >= visibleIndices.length) actualNew = visibleIndices.last + 1;
              else actualNew = visibleIndices[newIdx];
              // To keep it simpler and robust, we will reorder the whole box using oldIdx/newIdx of visible list:
              _onReorder(actualOld, actualNew);
            },
            itemCount: visibleIndices.length,
            buildDefaultDragHandles: true,
            itemBuilder: (context, idx) {
              final actualIndex = visibleIndices[idx];
              return Card(
                key: ValueKey('visible_${actualIndex}'),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: idx,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                    Expanded(child: _tileForIndex(actualIndex)),
                  ],
                ),
              );
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
