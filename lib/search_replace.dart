// lib/search_replace.dart
import 'package:flutter/material.dart';

class SearchReplaceSheet extends StatefulWidget {
  final TextEditingController controller;
  final ValueNotifier<List<TextRange>> highlightNotifier;

  SearchReplaceSheet({required this.controller, required this.highlightNotifier});

  @override
  _SearchReplaceSheetState createState() => _SearchReplaceSheetState();
}

class _SearchReplaceSheetState extends State<SearchReplaceSheet> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  bool _caseSensitive = false;
  bool _wholeWord = false;

  List<RegExpMatch> _matches = [];
  int _currentMatchIndex = -1;

  RegExp _makeRegex(String pattern) {
    if (pattern.isEmpty) return RegExp(r'(?!)'); // matches nothing
    final escaped = RegExp.escape(pattern);
    final expr = _wholeWord ? r'\b' + escaped + r'\b' : escaped;
    return RegExp(expr, caseSensitive: _caseSensitive, multiLine: true);
  }

  void _updateMatches() {
    final text = widget.controller.text;
    final patt = _findController.text;
    if (patt.isEmpty) {
      _matches = [];
      _currentMatchIndex = -1;
      widget.highlightNotifier.value = [];
      setState(() {});
      return;
    }
    final reg = _makeRegex(patt);
    final matches = reg.allMatches(text).toList();
    _matches = matches;
    if (_matches.isNotEmpty) {
      // set current to 0 if it was -1
      if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) {
        _currentMatchIndex = 0;
      }
      _applyHighlights();
      _selectMatchAt(_currentMatchIndex);
    } else {
      _currentMatchIndex = -1;
      widget.highlightNotifier.value = [];
    }
    setState(() {});
  }

  void _applyHighlights() {
    final ranges = <TextRange>[];
    for (final m in _matches) {
      ranges.add(TextRange(start: m.start, end: m.end));
    }
    widget.highlightNotifier.value = ranges;
  }

  void _selectMatchAt(int idx) {
    if (idx < 0 || idx >= _matches.length) return;
    final m = _matches[idx];
    widget.controller.selection = TextSelection(baseOffset: m.start, extentOffset: m.end);
    setState(() {
      _currentMatchIndex = idx;
    });
  }

  void _findNext() {
    _updateMatchesIfNeeded();
    if (_matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matches')));
      return;
    }
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    _selectMatchAt(_currentMatchIndex);
  }

  void _findPrev() {
    _updateMatchesIfNeeded();
    if (_matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matches')));
      return;
    }
    _currentMatchIndex = (_currentMatchIndex - 1);
    if (_currentMatchIndex < 0) _currentMatchIndex = _matches.length - 1;
    _selectMatchAt(_currentMatchIndex);
  }

  void _updateMatchesIfNeeded() {
    final patt = _findController.text;
    if (patt.isEmpty) return;
    _updateMatches();
  }

  // Replace current selection (if it matches), then automatically move to next
  void _replaceCurrentAndNext() {
    if (_matches.isEmpty || _currentMatchIndex == -1) {
      _findNext();
      return;
    }
    final match = _matches[_currentMatchIndex];
    final sel = widget.controller.selection;
    // If current selection corresponds to this match, replace it; otherwise select this match first
    final matchesSel = (sel.start == match.start && sel.end == match.end);
    if (!matchesSel) {
      _selectMatchAt(_currentMatchIndex);
    }

    final newTextPiece = _replaceController.text;
    final fullText = widget.controller.text;
    final newFull = fullText.replaceRange(match.start, match.end, newTextPiece);
    widget.controller.text = newFull;

    // After replacement, recompute matches and move to next instance (which may be at same index)
    final nextIndex = _currentMatchIndex; // try same index
    _updateMatches();
    if (_matches.isEmpty) {
      _currentMatchIndex = -1;
      widget.highlightNotifier.value = [];
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Replaced — no more matches')));
      setState(() {});
      return;
    }

    if (nextIndex >= 0 && nextIndex < _matches.length) {
      _selectMatchAt(nextIndex);
    } else {
      _selectMatchAt(0);
    }
  }

  void _replaceAll() {
    final patt = _findController.text;
    if (patt.isEmpty) return;
    final reg = _makeRegex(patt);
    final replaced = widget.controller.text.replaceAll(reg, _replaceController.text);
    widget.controller.text = replaced;
    _updateMatches();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All occurrences replaced')));
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _matches.length;
    final current = (_currentMatchIndex == -1) ? 0 : (_currentMatchIndex + 1);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: _findController, decoration: const InputDecoration(labelText: 'Find'), onChanged: (_) => _updateMatches())),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _findPrev, child: const Text('Prev')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _findNext, child: const Text('Next')),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('Matches: $current / $total', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(controller: _replaceController, decoration: const InputDecoration(labelText: 'Replace with')),
          Row(children: [
            Checkbox(value: _caseSensitive, onChanged: (v) => setState(() { _caseSensitive = v ?? false; _updateMatches(); })),
            const Text('Case sensitive'),
            const SizedBox(width: 16),
            Checkbox(value: _wholeWord, onChanged: (v) => setState(() { _wholeWord = v ?? false; _updateMatches(); })),
            const Text('Whole word'),
            const Spacer(),
            ElevatedButton(onPressed: _replaceCurrentAndNext, child: const Text('Replace')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _replaceAll, child: const Text('Replace all')),
          ]),
        ]),
      ),
    );
  }
}
