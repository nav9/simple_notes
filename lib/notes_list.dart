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
import 'about.dart';
import 'settings.dart';
import 'package:file_picker/file_picker.dart';
import 'password_dialog.dart';
import 'package:open_filex/open_filex.dart';


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

bool _contentLooksEncrypted(String content) {
  return content.startsWith('[ENCRYPTED]');
}

bool get _hasAnyNotes {
  for (final n in notesBox.values) {
    if (!(n['isTrashed'] ?? false)) return true;
  }
  return false;
}

bool get _hasDecryptedNotes {
  for (int i = 0; i < notesBox.length; i++) {
    final key = notesBox.keyAt(i);
    if (_session.getNotePassword(key)?.isNotEmpty == true) {
      return true;
    }
  }
  return false;
}

  // Encrypt all notes that we currently have decrypted in memory (use stored per-note passwords).
  Future<void> _encryptAllDecryptedNotes() async {
    try {
      if (_decryptedNotesCache.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No decrypted notes in session to encrypt.')));
        _session.clearAllNotePasswords();
        setState(() {});
        return;
      }
      for (final entry in _decryptedNotesCache.entries.toList()) {
        final key = entry.key;
        final plain = entry.value;
        final pw = _session.getNotePassword(key);
        if (pw == null || pw.isEmpty) continue;
        final enc = EncryptionService.encryptText(plain, pw);
        final old = notesBox.get(key);
        final updated = {'content': enc, 'isEncrypted': true, 'title': old?['title'] ?? null, 'isTrashed': old?['isTrashed'] ?? false};
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

Future<String?> _pickExportDirectory() async {
  final settingsBox = Hive.box('settings');

  // Ask user
  final String? dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select export folder',);

  if (dir == null) return null;

  // Save as default?
  final saveDefault = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Set as default?'),
      content: const Text('Use this folder as the default export location?',),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No'),),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes'),),
      ],
    ),
  );

  if (saveDefault == true) {settingsBox.put('exportDir', dir);}

  return dir;
}

Future<Directory> _getDefaultExportDirectory() async {
  if (Platform.isAndroid) {
    final dir = await getExternalStorageDirectory();
    final exportDir = Directory('${dir!.path}/exports');
    await exportDir.create(recursive: true);
    return exportDir;
  }
  if (Platform.isLinux) {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    await exportDir.create(recursive: true);
    return exportDir;
  }
  final dir = await getApplicationDocumentsDirectory();
  return dir;  
}

Future<Directory> resolveFolderSetting(String key) async {
  final settings = Hive.box('settings');
  final saved = settings.get(key);

  if (saved is String && saved.isNotEmpty) {
    final dir = Directory(saved);
    if (await dir.exists()) return dir;
  }

  // fallback
  final fallback = await _getDefaultExportDirectory();
  settings.put(key, fallback.path);
  return fallback;
}


Future<bool> _ensureStoragePermission() async {
  if (!Platform.isAndroid) return true;

  final status = await Permission.manageExternalStorage.request();
  return status.isGranted;
}

  // Move selected notes to trash
  Future<void> _moveSelectedToTrash() async {
    try {
      final keys = List<dynamic>.from(_selectedKeys);
      for (final key in keys) {
        final idx = _indexOfKey(key);
        if (idx == -1) continue;
        final note = notesBox.get(key)!;
        final updated = Map<String, dynamic>.from(note);
        updated['isTrashed'] = true;
        await notesBox.put(key, updated);
        _decryptedNotesCache.remove(key);
        _session.clearNotePassword(key);
      }
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
    setState(() {if (_selectedKeys.contains(key)) _selectedKeys.remove(key); else _selectedKeys.add(key);});
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
    setState(() {_selectedKeys.clear();});
  }

  // Duplicate selected notes
  Future<void> _duplicateSelected() async {
    try {
      final keysToDup = List<dynamic>.from(_selectedKeys);
      for (final key in keysToDup) {
        final note = await notesBox.get(key) as Map?;
        if (note == null) continue;
        final title = (note['title'] as String?) ?? '';
        final isEncrypted = (note['isEncrypted'] ?? false) as bool;

        final baseTitle = title.isNotEmpty ? title : 'note';
        final nextTitle = _nextCopyTitle(baseTitle);

        if (isEncrypted) {
          final newNote = {'content': note['content'], 'isEncrypted': true, 'title': nextTitle, 'isTrashed': false,};
          final List<Map> tempList = [Map<String, dynamic>.from(newNote)];
          tempList.addAll(notesBox.values.map((e) => Map<String, dynamic>.from(e)));
          await notesBox.clear();
          await notesBox.addAll(tempList);
        } else {
          final sessionPw = _session.getNotePassword(key);
          String? plain;
          if (sessionPw != null && sessionPw.isNotEmpty) {
            final tryDec = EncryptionService.decryptText(note['content'] as String, sessionPw);
            if (tryDec != null) plain = tryDec; else plain = note['content'] as String;
          } else {plain = note['content'] as String;}

          final newNote = {'content': plain, 'isEncrypted': false, 'title': nextTitle, 'isTrashed': false,};
          final List<Map> tempList = [Map<String, dynamic>.from(newNote)];
          tempList.addAll(notesBox.values.map((e) => Map<String, dynamic>.from(e)));
          await notesBox.clear();
          await notesBox.addAll(tempList);
        }
      }

      _selectedKeys.clear();
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duplicated selected notes')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Duplicate failed: $e')));
    }
  }

Future<Directory> _resolveExportDirectory() async {
  final settings = Hive.box('settings');

  // Always start from resolved folder
  final baseDir = await resolveFolderSetting('exportDir');
  final picked = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select export folder', initialDirectory: baseDir.path,);

  if (picked != null) {
    settings.put('exportDir', picked);
    final dir = Directory(picked);
    await dir.create(recursive: true);
    return dir;
  }

  return baseDir;
}


void _showExportSuccess(String path) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Export successful'),
      content: Text('Saved to:\n$path'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'),),
        TextButton(
          onPressed: () {
            if (!Platform.isLinux) {OpenFilex.open(path);}
            Navigator.pop(context);
          },
          child: const Text('Open Folder'),
        ),
      ],
    ),
  );
}


  // Helper: find next available copy title e.g., "Name_copy1", "_copy2", etc.
  String _nextCopyTitle(String base) {
    final existingTitles = <String>{};
    for (int i = 0; i < notesBox.length; i++) {
      final n = notesBox.getAt(i)!;
      final t = (n['title'] as String?) ?? '';
      if (t.isNotEmpty) existingTitles.add(t);
    }

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
    final settings = Hive.box('settings');
    final defaultDir = (await resolveFolderSetting('importDir')).path;

    final res = await FilePicker.platform.pickFiles(allowMultiple: true, initialDirectory: defaultDir, type: FileType.custom,allowedExtensions: ['txt'],);

    if (res == null) return;

    // Save folder user actually used
    final usedPath = p.dirname(res.files.first.path!);
    settings.put('importDir', usedPath);

    for (final f in res.files) {
      final content = await File(f.path!).readAsString();
      final isEncrypted = content.startsWith('[ENCRYPTED]');
      final title = p.basenameWithoutExtension(f.path!);

      await notesBox.add({'content': content, 'isEncrypted': isEncrypted, 'title': title, 'isTrashed': false,});
    }

    if (mounted) setState(() {});
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}

  // Export selected notes if any selected, else export all notes to folder; uses title as filename if present, otherwise unique ordinal
Future<void> _exportAllOrSelected() async {
  try {
    if (!await _ensureStoragePermission()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied')),);
      return;
    }

    final exportDir = await _resolveExportDirectory();

    final keysToExport = _selectedKeys.isNotEmpty ? List<dynamic>.from(_selectedKeys) : List<dynamic>.from(notesBox.keys);

    int ordinal = 1;
    for (final key in keysToExport) {
      final n = notesBox.get(key);
      if (n == null || (n['isTrashed'] ?? false)) continue;

      final title = (n['title'] as String?)?.trim();
      String filename = (title != null && title.isNotEmpty) ? title : 'note_${ordinal++}';

      if (!filename.toLowerCase().endsWith('.txt')) {filename = '$filename.txt';}

      final filePath = p.join(exportDir.path, filename);
      await File(filePath).writeAsString(n['content']);
    }

    _showExportSuccess(exportDir.path);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}


  Future<void> _mergeSelectedNotes() async {
    try {
      if (_selectedKeys.length < 2) return;

      // Preserve visible order
      final orderedKeys = <dynamic>[];
      for (int i = 0; i < notesBox.length; i++) {
        final key = notesBox.keyAt(i);
        if (_selectedKeys.contains(key)) orderedKeys.add(key);
      }

      final Map<String, String> passwordCache = {};
      final buffer = StringBuffer();

      for (final key in orderedKeys) {
        final note = notesBox.get(key)!;
        String content = note['content'] as String;
        final isEncrypted = note['isEncrypted'] ?? false;

        if (isEncrypted) {
          String? decrypted;

          // Try known passwords
          for (final pw in passwordCache.values) {
            decrypted = EncryptionService.decryptText(content, pw);
            if (decrypted != null) break;
          }

          // Try session password
          final sessionPw = _session.getNotePassword(key);
          if (decrypted == null && sessionPw != null) {
            decrypted = EncryptionService.decryptText(content, sessionPw);
            if (decrypted != null) {passwordCache[key.toString()] = sessionPw;}
          }

          // Ask user
          while (decrypted == null) {
            final pw = await showPasswordDialog(context, 'Password for "${note['title'] ?? 'Encrypted note'}"', false,);
            if (pw == null || pw.isEmpty) return;
            decrypted = EncryptionService.decryptText(content, pw);
            if (decrypted != null) {passwordCache[key.toString()] = pw;}
          }

          content = decrypted;
        }

        final title = (note['title'] as String?)?.trim();
        if (title != null && title.isNotEmpty) {buffer.writeln(title);}
        buffer.writeln(content);
        buffer.writeln();
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final newNote = {'title': 'Merged$timestamp.txt', 'content': buffer.toString().trim(), 'isEncrypted': false, 'isTrashed': false,};

      final List<Map> temp = [newNote];
      temp.addAll(notesBox.values.map((e) => Map<String, dynamic>.from(e)));
      await notesBox.clear();
      await notesBox.addAll(temp);

      _selectedKeys.clear();
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notes merged successfully')),);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Merge failed: $e')),);
    }
  }

  // Build tile
  Widget _tileForIndex(int index) {
    final note = notesBox.getAt(index)!;
    final key = notesBox.keyAt(index);
    final isTrashed = note['isTrashed'] ?? false;
    if (isTrashed) return SizedBox.shrink();

    final content = note['content'] as String;
    final isEncrypted = (note['isEncrypted'] ?? false) || _contentLooksEncrypted(content);

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
        if (sessionPw != null && sessionPw.isNotEmpty) {displaySubtitle = 'Decrypted';}
        else {displaySubtitle = '🔒 Encrypted';}
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
      leading: Checkbox(value: _selectedKeys.contains(key), onChanged: (_) => _toggleSelection(key),),
      title: Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: displaySubtitle.isNotEmpty ? Text(displaySubtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: isEncrypted
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isDecryptedInSession ? Icons.lock_open : Icons.lock),
              if (isDecryptedInSession) const SizedBox(width: 6),
              if (isDecryptedInSession) const Text('Decrypted', style: TextStyle(color: Colors.lightBlue))
            ])
          : null,
      onTap: () {
        final content = note['content'] as String;
        final initialIsEncrypted = (note['isEncrypted'] ?? false) as bool;
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => EditNoteScreen(index: index, noteKey: key, note: content, initialIsEncrypted: initialIsEncrypted)),
        ).then((_) {if (mounted) setState(() {});});
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
        if (pw != null && pw.isNotEmpty) _session.storeNotePassword(k, pw);
        else _session.clearNotePassword(k);
      }

      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
    }
  }

  // New note action in AppBar
  void _createNewNote() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditNoteScreen())).then((_) {if (mounted) setState(() {});});
  }

  List<PopupMenuEntry<String>> _buildMainMenuItems(BuildContext context) {
    final hasSelection = _selectedKeys.isNotEmpty;
    final multipleSelected = _selectedKeys.length > 1;

    return [
      if (_hasAnyNotes) const PopupMenuItem(value: 'select_all',child: ListTile(leading: Icon(Icons.select_all), title: Text('Select All'),),),
      if (hasSelection) ...[        
        const PopupMenuItem(value: 'select_none',child: ListTile(leading: Icon(Icons.clear), title: Text('Select None'),),),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'duplicate',child: ListTile(leading: Icon(Icons.control_point_duplicate),title: Text('Duplicate'),),),
        const PopupMenuItem(value: 'export_selected',child: ListTile(leading: Icon(Icons.download_outlined),title: Text('Export'),),),
        if (multipleSelected) const PopupMenuItem(value: 'merge',child: ListTile(leading: Icon(Icons.merge_type), title: Text('Merge'),),),
        const PopupMenuItem(value: 'trash',child: ListTile(leading: Icon(Icons.delete), title: Text('Delete'),),),
        const PopupMenuDivider(),
      ],
      if (_hasDecryptedNotes) const PopupMenuItem(value: 'encrypt_all',child: ListTile(leading: Icon(Icons.lock),title: Text('Encrypt all decrypted notes'),),),
      if (_hasAnyNotes) const PopupMenuItem(value: 'export_all',child: ListTile(leading: Icon(Icons.file_download),title: Text('Export All'),),),
      const PopupMenuItem(value: 'import',child: ListTile(leading: Icon(Icons.file_upload),title: Text('Import Notes'),),),
    ];
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'select_all':
        _selectAll();
        break;
      case 'select_none':
        _selectNone();
        break;
      case 'duplicate':
        _duplicateSelected();
        break;
      case 'trash':
        _moveSelectedToTrash();
        break;
      case 'encrypt_all':
        _encryptAllDecryptedNotes();
        break;
      case 'export_selected':
      case 'export_all':
        _exportAllOrSelected();
        break;
      case 'import':
        _importNotes();
        break;
      case 'merge':
        _mergeSelectedNotes();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Notes'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.lightBlue),
              tooltip: 'New Note',
              onPressed: _createNewNote),
          PopupMenuButton<String>(onSelected: _handleMenuAction, itemBuilder: _buildMainMenuItems,),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(child: Text('Menu',style: Theme.of(context).textTheme.headlineSmall)),
            ListTile(leading: const Icon(Icons.settings),title: const Text('Settings'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context,MaterialPageRoute(builder: (_) => const SettingsScreen()),);
                    },
                  ),
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
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => AboutScreen()),);
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

          if (visibleIndices.isEmpty)
            return const Center(child: Text('No notes. Use New Note to create or import one.'));

          return ReorderableListView.builder(
            onReorder: (oldIdx, newIdx) {
              final actualOld = visibleIndices[oldIdx];
              int actualNew;
              if (newIdx >= visibleIndices.length) actualNew = visibleIndices.last + 1;
              else actualNew = visibleIndices[newIdx];
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
    );
  }
}
