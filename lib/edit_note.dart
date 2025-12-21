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

  EditNoteScreen({
    this.index,
    this.noteKey,
    this.note,
    this.initialIsEncrypted = false,
  });

  @override
  _EditNoteScreenState createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  late HighlightTextEditingController _textController;
  final _titleController = TextEditingController();
  final _focusNode = FocusNode();
  late final bool _enableHighlighting;


  /// NEW: Scroll controller for editor
  final ScrollController _scrollController = ScrollController();

  /// NEW: Cursor overlay fix
  bool _ignorePointerForEditorField = false;

  /// Highlight ranges (used to mark matches)
  final ValueNotifier<List<TextRange>> _highlights =
      ValueNotifier<List<TextRange>>([]);

  /// NEW: Index of current match
  final ValueNotifier<int> _currentMatchIndex = ValueNotifier<int>(0);

  bool _isReadOnlyEncrypted = false;
  bool _isEditing = false;
  TextSelection? _lastSelection;
  String? _originalTextSnapshot;
  String? _originalTitleSnapshot;
  final _notesBox = Hive.box<Map>('notesBox');
  final _session = SessionManager();
  String _lastKnownText = '';

  @override
  void initState() {
    super.initState();
    _enableHighlighting = !Platform.isAndroid;
    final content = widget.note ?? '';
    // Initialize tracker
    _lastKnownText = content;    
    if (_enableHighlighting) {_textController = HighlightTextEditingController(text: content, baseStyle: const TextStyle(fontSize: 16, height: 1.4),);} 
    else {_textController = HighlightTextEditingController(text: content, baseStyle: const TextStyle(fontSize: 16, height: 1.4),)
        ..highlights = []; // no highlights ever
    }

    _originalTextSnapshot = content;

    if (widget.noteKey != null) {
      final entry = _notesBox.get(widget.noteKey);
      if (entry != null && entry['title'] != null) {
        _titleController.text = entry['title'] as String;
        _originalTitleSnapshot = _titleController.text;
      }
    }

    // Encryption handling
    final isEncryptedContent =
        content.startsWith('[ENCRYPTED]') || widget.initialIsEncrypted;
    final sessionPw = _session.getNotePassword(widget.noteKey);
    if (isEncryptedContent && sessionPw == null) {
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

      // ONLY clear highlights if the text CONTENT has changed.
      // This prevents infinite loops when notifyListeners() is called
      // for selection changes or highlight updates.
      if (_textController.text != _lastKnownText) {
        _lastKnownText = _textController.text;

        // Only clear if we actually have highlights to clear
        if (_highlights.value.isNotEmpty) {
          _highlights.value = [];
          _textController.highlights = [];
        }
      }
    });

// CHANGE 4: Listen to _highlights value notifier to update the controller
    _highlights.addListener(() {
      if (!_enableHighlighting) return;
      _textController.highlights = _highlights.value;
      // Force a repaint of the text
      _textController.notifyListeners();
    });

// CHANGE 5: Listen to match index to update the active color
    _currentMatchIndex.addListener(() {
      if (!_enableHighlighting) return;
      _textController.currentMatchIndex = _currentMatchIndex.value;
      _textController.notifyListeners();
    });
  }

  void _handleEditorMenuAction(String action) {
    switch (action) {
      case 'search':
        _openSearchReplace();
        break;
      case 'copy':
        _copyToClipboard();
        break;
      // case 'encrypt':
      //   _isReadOnlyEncrypted ? _decryptInEditor() : _encryptInEditor();
      //   break;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _highlights.dispose();
    _currentMatchIndex.dispose();
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

  Future<void> _saveNote({bool popAfterSave = false}) async {
    try {
      final content = _textController.text;
      final titleText = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final sessionPw = widget.noteKey != null ? _session.getNotePassword(widget.noteKey) : _session.sessionPassword;
      final shouldEncryptOnDisk = sessionPw != null && sessionPw.trim().isNotEmpty;

      final newNote = {
        'content': shouldEncryptOnDisk ? EncryptionService.encryptText(content, sessionPw!) : content,
        'isEncrypted': shouldEncryptOnDisk,
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

      if (shouldEncryptOnDisk) {
        if (widget.noteKey != null) {_session.storeNotePassword(widget.noteKey, sessionPw!);}
        else {_session.sessionPassword = sessionPw!;}
      } else {
        if (widget.noteKey != null) {_session.clearNotePassword(widget.noteKey);}
      }

      _originalTextSnapshot = content;
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
    _highlights.value = []; // Clear highlights on exit
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
        await _saveNote(popAfterSave: false);
        return true;
      }
      return shouldSave != null;
    }
    return true;
  }

  Future<void> _copyToClipboard() async {
    try {
      final title = _titleController.text.trim();
      final content = _textController.text;
      final buffer = StringBuffer();
      if (title.isNotEmpty) {//join the title and content
        buffer.writeln(title);
        //buffer.writeln();//empty line
      }
      buffer.write(content);  
      final textToCopy = buffer.toString();
      if (textToCopy.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to copy')),);
        return;
      }    
      await Clipboard.setData(ClipboardData(text: textToCopy));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')),);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy failed: $e')),);
    }
  }

  Future<void> _decryptInEditor() async {
    final password = await showPasswordDialog(context, "Enter password to decrypt note", false,);
    if (password == null || password.isEmpty) return;

    final decrypted = EncryptionService.decryptText(_textController.text, password,);

    if (decrypted != null) {
      if (widget.noteKey != null) {_session.storeNotePassword(widget.noteKey, password);} 
      else {_session.sessionPassword = password;}

      setState(() {
        _textController.text = decrypted;
        _lastKnownText = decrypted;
        _originalTextSnapshot = decrypted;
        _isReadOnlyEncrypted = false;
      });

      Future.delayed(const Duration(milliseconds: 50),() => _focusNode.requestFocus(),);

      if (mounted) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decrypted successfully')),);}
    } else {
      if (mounted) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed. Wrong password?')),);}
    }
  }

  Future<void> _encryptInEditor() async {
    try {
      String? pw = widget.noteKey != null ? _session.getNotePassword(widget.noteKey) : _session.sessionPassword;

      if (pw == null || pw.isEmpty) {
        final entered = await showPasswordDialog(context, "Set password to encrypt note", true,);
        if (entered == null || entered.isEmpty) return;
        pw = entered;

        if (widget.noteKey != null) {_session.storeNotePassword(widget.noteKey, pw);} else {_session.sessionPassword = pw;}
      }

      final encryptedText = EncryptionService.encryptText(_textController.text,pw!,);

      final Map newNote = {'content': encryptedText,'isEncrypted': true, 'title': _titleController.text.trim().isEmpty ? null : _titleController.text.trim(), 'isTrashed': false,};

      if (widget.index != null) {await _notesBox.putAt(widget.index!, newNote);} 
      else {
        final List<Map> temp = [Map<String, dynamic>.from(newNote)];
        temp.addAll(_notesBox.values.map((e) => Map<String, dynamic>.from(e)),);
        await _notesBox.clear();
        await _notesBox.addAll(temp);
      }

      // Clear password from session
      if (widget.noteKey != null) {_session.clearNotePassword(widget.noteKey);} else {_session.sessionPassword = null;}

      setState(() {
        _textController.text = encryptedText;
        _lastKnownText = encryptedText;
        _originalTextSnapshot = encryptedText;
        _isReadOnlyEncrypted = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note encrypted. Password cleared from session; re-enter to decrypt later.',),),);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encryption failed: $e')),);
    }
  }

  // Scroll to a given range
  void _scrollToRange(TextRange range) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pos = range.start;
      final text = _textController.text;
      final before = text.substring(0, pos).split('\n').length; // approx line number
      final offset = (before - 1) * 22.0; // approx line height
      _scrollController.animateTo(offset, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,);
    });
  }

  Future<void> _openSearchReplace() async {
    final result = await showModalBottomSheet<SearchReplaceResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SearchReplaceSheet(controller: _textController, highlightNotifier: _highlights,currentMatchNotifier: _currentMatchIndex,),
    );

    if (result != null && result.jumpTo != null) {_scrollToRange(result.jumpTo!);}
  }

  // Build highlighted text behind transparent editor
  Widget _buildHighlightedText() {
    if (!_enableHighlighting) {
    final text = _textController.text;
    if (text.isEmpty) {return const SizedBox.shrink();}

    return Text(text, softWrap: true, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4,),);
  }
    return ValueListenableBuilder<List<TextRange>>(
      valueListenable: _highlights,
      builder: (context, ranges, _) {
        final text = _textController.text;
        if (text.isEmpty) {return const SizedBox.shrink();}
        if (ranges.isEmpty) {return Text(text, style: const TextStyle(color: Colors.white70, fontSize: 16),);}

        ranges = List.from(ranges)..sort((a, b) => a.start.compareTo(b.start));
        final spans = <TextSpan>[];
        int cursor = 0;

        for (int i = 0; i < ranges.length; i++) {
          final r = ranges[i];
          if (r.start > cursor) {spans.add(TextSpan(text: text.substring(cursor, r.start)));}

          final isCurrentMatch = i == _currentMatchIndex.value;

          spans.add(TextSpan(text: text.substring(r.start, r.end), style: TextStyle(backgroundColor: isCurrentMatch ? Colors.orange : const Color(0xFF4444AA), color: Colors.white,),));
          cursor = r.end;
        }

        if (cursor < text.length) {spans.add(TextSpan(text: text.substring(cursor)));}

        return Text.rich(TextSpan(children: spans), softWrap: true, style: const TextStyle(fontSize: 16, height: 1.4),);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canInsertTime = !_isReadOnlyEncrypted && (_isEditing || _lastSelection != null);

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
                icon: Icon(_isReadOnlyEncrypted ? Icons.lock_open : Icons.lock_outline, color: Colors.lightBlue,),
                onPressed: () => _isReadOnlyEncrypted ? _decryptInEditor() : _encryptInEditor(),
                tooltip: _isReadOnlyEncrypted ? 'Decrypt' : 'Encrypt',),              
              IconButton(icon: const Icon(Icons.access_time, color: Colors.lightBlue), onPressed: canInsertTime ? _insertCurrentTime : null,),
              IconButton(icon: const Icon(Icons.save, color: Colors.lightBlue), onPressed: _isReadOnlyEncrypted ? null : () => _saveNote(popAfterSave: true),),
              PopupMenuButton<String>(
                onSelected: _handleEditorMenuAction,
                itemBuilder: (_) => [
                  if (_enableHighlighting) const PopupMenuItem(value: 'search', child: ListTile(leading: Icon(Icons.search), title: Text('Search'),),),                  
                  const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.content_copy), title: Text('Copy'),),),
                  //PopupMenuItem(value: 'encrypt', child: ListTile(leading: Icon(_isReadOnlyEncrypted ? Icons.lock_open : Icons.lock_outline), title: Text(_isReadOnlyEncrypted ? 'Decrypt' : 'Encrypt'),),),  
                  //const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.file_download), title: Text('Export'),),),
                ],
              ),
            ],

          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'Identifying name (not encrypted)',),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_focusNode),
                  enableSuggestions: false,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Listener(
                    onPointerDown: (_) {
                      // allow editor pointer events only when selecting text
                      setState(() {_ignorePointerForEditorField = false;});
                    },
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      // Important: Pass the scroll controller here so _scrollToRange works
                      scrollController: _scrollController,
                      readOnly: _isReadOnlyEncrypted,
                      maxLines: null,
                      expands: true, // Fills the Expanded parent
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(border: OutlineInputBorder(),hintText: 'Enter your note',),
                      // CHANGE 7: Restore normal styles and physics
                      style: const TextStyle(fontSize: 16,height: 1.4,color: Colors.black // Ensure text is visible
                          ),
                      cursorColor: Colors.blue,
                      // Use normal physics or AlwaysScrollableScrollPhysics
                      scrollPhysics: const AlwaysScrollableScrollPhysics(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyF) {
        _openSearchReplace();
      } else if (event.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveNote(popAfterSave: false);
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (Navigator.canPop(context)) Navigator.maybePop(context);
      }
    }
  }

  Future<void> _insertCurrentTime() async {
    if (_isReadOnlyEncrypted) return;
    final sel = _textController.selection;
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ";

    final text = _textController.text;
    final newText = text.replaceRange(sel.start, sel.end, timeStr);
    _textController.text = newText;
    _textController.selection = TextSelection.collapsed(offset: sel.start + timeStr.length);
  }
}

/// A custom controller that highlights text ranges based on search matches
class HighlightTextEditingController extends TextEditingController {
  List<TextRange> highlights = [];
  int currentMatchIndex = 0;

  // Colors
  final Color matchColor = const Color(0xFF4444AA);
  final Color currentMatchColor = Colors.orange;
  final TextStyle baseStyle;

  HighlightTextEditingController({
    required String text,
    this.baseStyle = const TextStyle(fontSize: 16, height: 1.4, color: Colors.black),
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({required BuildContext context,TextStyle? style,required bool withComposing,}) {
    // If no highlights, just return standard text
    if (highlights.isEmpty) {return TextSpan(text: text, style: baseStyle);}

    // Sort ranges just to be safe
    final sortedRanges = List<TextRange>.from(highlights)
      ..sort((a, b) => a.start.compareTo(b.start));

    final spans = <TextSpan>[];
    int cursor = 0;

    for (int i = 0; i < sortedRanges.length; i++) {
      final range = sortedRanges[i];

      // Add non-highlighted text before the match
      if (range.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.start),style: baseStyle,));
      }

      // Add the highlighted match
      // Ensure we don't crash if range is out of bounds (safety check)
      if (range.end <= text.length) {
        final isCurrent = (i == currentMatchIndex);
        spans.add(TextSpan(text: text.substring(range.start, range.end),style: baseStyle.copyWith(backgroundColor: isCurrent ? currentMatchColor : matchColor,color: Colors.white,),));
      }

      cursor = range.end;
    }

    // Add remaining text
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor),style: baseStyle,));
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}
