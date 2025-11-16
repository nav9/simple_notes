// lib/edit_note.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'session_manager.dart';
import 'encryption_service.dart';
import 'search_replace.dart';
import 'password_dialog.dart';

class EditNoteScreen extends StatefulWidget {
  final int? index;
  final dynamic? noteKey;
  final String? note;
  final bool initialIsEncrypted;

  EditNoteScreen({this.index, this.noteKey, this.note, this.initialIsEncrypted = false});

  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final _focusNode = FocusNode();

  // notifier for highlighted ranges (used by highlight overlay)
  final ValueNotifier<List<TextRange>> _highlights = ValueNotifier<List<TextRange>>([]);

  bool _isReadOnlyEncrypted = false;
  bool _isEditing = false;
  TextSelection? _lastSelection;
  String? _originalTextSnapshot;
  String? _originalTitleSnapshot;
  final _notesBox = Hive.box<Map>('notesBox');
  final _session = SessionManager();

  @override
  void initState() {
    super.initState();
    final content = widget.note ?? '';
    _textController.text = content;
    _originalTextSnapshot = content;

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
      // whenever text changes we should update highlights (they may now be stale)
      _highlights.value = [];
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _focusNode.dispose();
    _highlights.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final currentText = _textController.text;
    final currentTitle = _titleController.text;
    if (_originalTextSnapshot != null && currentText != _originalTextSnapshot) return true;
    if (_originalTitleSnapshot != null && currentTitle != _originalTitleSnapshot) return true;
    if (_originalTextSnapshot == null && currentText.trim().isNotEmpty) return true;
    if (_originalTitleSnapshot == null && currentTitle.trim().isNotEmpty) return true;
    return false;
  }

  // IMPORTANT: _saveNote does NOT pop by default. Caller decides whether to pop.
  Future<void> _saveNote({bool popAfterSave = false}) async {
    try {
      final content = _textController.text;
      final titleText = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final sessionPw = widget.noteKey != null ? _session.getNotePassword(widget.noteKey) : _session.sessionPassword;
      final shouldEncryptOnDisk = sessionPw != null && sessionPw.isNotEmpty;

      if (shouldEncryptOnDisk) {
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

        if (widget.noteKey != null) _session.storeNotePassword(widget.noteKey, sessionPw);
        else _session.sessionPassword = sessionPw;
        _originalTextSnapshot = content;
      } else {
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

      if (popAfterSave && mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<bool> _onWillPop() async {
    // If ESC pressed or back navigation, clear highlights
    _highlights.value = [];
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
      if (shouldSave == true) {
        // Save but do not pop twice: save without popping, then allow the WillPopScope to pop.
        await _saveNote(popAfterSave: false);
        return true;
      }
      return shouldSave != null;
    }
    return true;
  }

  Future<void> _copyToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: _textController.text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy failed: $e')));
    }
  }

  Future<void> _decryptInEditor() async {
    final password = await showPasswordDialog(context, "Enter password to decrypt note", false);
    if (password == null || password.isEmpty) return;
    final decrypted = EncryptionService.decryptText(_textController.text, password);
    if (decrypted != null) {
      if (widget.noteKey != null) _session.storeNotePassword(widget.noteKey, password);
      else _session.sessionPassword = password;
      setState(() {
        _textController.text = decrypted;
        _originalTextSnapshot = decrypted;
        _isReadOnlyEncrypted = false;
      });
      Future.delayed(const Duration(milliseconds: 50), () => _focusNode.requestFocus());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decrypted successfully')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')));
    }
  }

  Future<void> _encryptInEditor() async {
    try {
      String? pw = widget.noteKey != null ? _session.getNotePassword(widget.noteKey) : _session.sessionPassword;
      if (pw == null || pw.isEmpty) {
        final p = await showPasswordDialog(context, "Set password to encrypt note", true);
        if (p == null || p.isEmpty) return;
        pw = p;
        if (widget.noteKey != null) _session.storeNotePassword(widget.noteKey, pw);
        else _session.sessionPassword = pw;
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
        final List<Map> temp = [Map<String, dynamic>.from(newNote)];
        temp.addAll(_notesBox.values.map((e) => Map<String, dynamic>.from(e)));
        await _notesBox.clear();
        await _notesBox.addAll(temp);
      }

      // After encrypting, clear the session password for this note
      if (widget.noteKey != null) _session.clearNotePassword(widget.noteKey);
      else _session.sessionPassword = null;

      setState(() {
        _textController.text = encryptedText;
        _originalTextSnapshot = encryptedText;
        _isReadOnlyEncrypted = true;
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note encrypted. Password cleared from session; re-enter to decrypt later.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encryption failed: $e')));
    }
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
      final rawName = (_titleController.text.trim().isNotEmpty) ? _titleController.text.trim() : 'note_${DateTime.now().millisecondsSinceEpoch}';
      String filename = rawName;
      if (!filename.toLowerCase().endsWith('.txt')) filename = '$filename.txt';
      final path = p.join(dir.path, filename);
      await File(path).writeAsString(_textController.text);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  void _openSearchReplace() {
    // show sheet and pass controller and highlight notifier
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SearchReplaceSheet(
        controller: _textController,
        highlightNotifier: _highlights,
      ),
    );
  }

  // Keyboard shortcuts for desktop (Linux)
  void _handleKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final isLinux = Platform.isLinux;
      // Use control for linux/desktop; also accept meta for others? We'll check ctrlKey.
      if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
        _openSearchReplace();
      } else if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyS) {
        // save
        _saveNote(popAfterSave: false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved (Ctrl+S)')));
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        // pop if possible
        if (Navigator.of(context).canPop()) Navigator.of(context).maybePop();
      }
    }
  }

  // Build highlighted RichText from controller.text and _highlights ranges
  Widget _buildHighlightedText() {
    return ValueListenableBuilder<List<TextRange>>(
      valueListenable: _highlights,
      builder: (context, ranges, _) {
        final text = _textController.text;
        if (text.isEmpty) {
          return const SizedBox.shrink();
        }
        if (ranges.isEmpty) {
          // no highlights — render plain text with default style
          return Text.rich(TextSpan(text: text, style: const TextStyle(color: Colors.white70, fontSize: 16)));
        }
        // sort and merge ranges to avoid overlap
        final sorted = List<TextRange>.from(ranges)..sort((a, b) => a.start.compareTo(b.start));
        final spans = <TextSpan>[];
        int cursor = 0;
        for (final r in sorted) {
          if (r.start > cursor) {
            spans.add(TextSpan(text: text.substring(cursor, r.start)));
          }
          // highlighted span
          spans.add(TextSpan(
              text: text.substring(r.start, r.end),
              style: const TextStyle(backgroundColor: Color(0xFF4444AA), color: Colors.white)));
          cursor = r.end;
        }
        if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
        return Text.rich(TextSpan(children: spans), softWrap: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canInsertTime = !_isReadOnlyEncrypted && (_isEditing || _lastSelection != null);

    // Wrap in RawKeyboardListener for desktop shortcuts
    return RawKeyboardListener(
      focusNode: FocusNode(),
      onKey: _handleKey,
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_titleController.text.trim().isNotEmpty ? _titleController.text.trim() : (widget.initialIsEncrypted ? 'Encrypted Note' : 'Edit Note')),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Find & Replace (Ctrl+F)',
                onPressed: _openSearchReplace,
              ),
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
                tooltip: 'Save (Ctrl+S)',
                onPressed: _isReadOnlyEncrypted ? null : () => _saveNote(popAfterSave: true),
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
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_focusNode),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Stack(
                    children: [
                      // Highlighted rich text behind
                      Positioned.fill(
                        child: Container(
                          padding: const EdgeInsets.all(8.0),
                          alignment: Alignment.topLeft,
                          child: SingleChildScrollView(
                            child: _buildHighlightedText(),
                          ),
                        ),
                      ),
                      // Transparent TextField on top for editing/caret
                      Positioned.fill(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          readOnly: _isReadOnlyEncrypted,
                          maxLines: null,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter your note',
                          ),
                          // make text transparent so underlying RichText is visible
                          style: TextStyle(color: Colors.transparent, fontSize: 16, height: 1.4),
                          cursorColor: Colors.white,
                          // ensure selection color remains visible (selection color is separate)
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
