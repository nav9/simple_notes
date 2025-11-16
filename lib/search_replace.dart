// lib/search_replace.dart
import 'package:flutter/material.dart';

/// Small result type (optional) returned by the sheet if the caller wants a final jump-to
class SearchReplaceResult {
  final TextRange? jumpTo;
  SearchReplaceResult({this.jumpTo});
}

class SearchReplaceSheet extends StatefulWidget {
  final TextEditingController controller;
  final ValueNotifier<List<TextRange>> highlightNotifier;
  final ValueNotifier<int>? currentMatchNotifier; // optional; when set, sheet updates it

  SearchReplaceSheet({
    required this.controller,
    required this.highlightNotifier,
    this.currentMatchNotifier,
  });

  @override
  _SearchReplaceSheetState createState() => _SearchReplaceSheetState();
}

class _SearchReplaceSheetState extends State<SearchReplaceSheet> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  bool _caseSensitive = false;
  bool _wholeWord = false;

  List<RegExpMatch> _matches = [];
  int _currentIndex = -1;

  RegExp _makeRegex(String pattern) {
    if (pattern.isEmpty) return RegExp(r'(?!)');
    final escaped = RegExp.escape(pattern);
    final expr = _wholeWord ? r'\b' + escaped + r'\b' : escaped;
    return RegExp(expr, caseSensitive: _caseSensitive, multiLine: true);
  }

  void _recomputeMatches({bool keepIndexIfPossible = true}) {
    final patt = _findController.text;
    if (patt.isEmpty) {
      _matches = [];
      _currentIndex = -1;
      widget.highlightNotifier.value = [];
      _notifyCurrentMatch();
      setState(() {});
      return;
    }
    final reg = _makeRegex(patt);
    final text = widget.controller.text;
    final matches = reg.allMatches(text).toList();
    // remember old position's matched substring so we can keep selection near same match if possible
    String? oldMatchText;
    if (_currentIndex >= 0 && _currentIndex < _matches.length) {
      oldMatchText = _matches[_currentIndex].group(0);
    }
    _matches = matches;

    if (_matches.isEmpty) {
      _currentIndex = -1;
      widget.highlightNotifier.value = [];
      _notifyCurrentMatch();
      setState(() {});
      return;
    }

    if (keepIndexIfPossible && oldMatchText != null) {
      // try to keep pointing to the nearest same-text match
      int newIdx = _matches.indexWhere((m) => m.group(0) == oldMatchText);
      if (newIdx == -1) newIdx = 0;
      _currentIndex = newIdx;
    } else {
      _currentIndex = 0;
    }

    _applyHighlights();
    _notifyCurrentMatch();
    _selectCurrentMatchInController();
    setState(() {});
  }

  void _applyHighlights() {
    final ranges = <TextRange>[];
    for (final m in _matches) {
      ranges.add(TextRange(start: m.start, end: m.end));
    }
    widget.highlightNotifier.value = ranges;
  }

  void _notifyCurrentMatch() {
    if (widget.currentMatchNotifier != null) {
      widget.currentMatchNotifier!.value = _currentIndex;
    }
  }

  void _selectCurrentMatchInController() {
    if (_currentIndex >= 0 && _currentIndex < _matches.length) {
      final m = _matches[_currentIndex];
      widget.controller.selection = TextSelection(baseOffset: m.start, extentOffset: m.end);
    }
  }

  void _next() {
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    _applyHighlights();
    _notifyCurrentMatch();
    _selectCurrentMatchInController();
    setState(() {});
  }

  void _prev() {
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex - 1);
    if (_currentIndex < 0) _currentIndex = _matches.length - 1;
    _applyHighlights();
    _notifyCurrentMatch();
    _selectCurrentMatchInController();
    setState(() {});
  }

  void _replaceCurrentAndNext() {
    if (_matches.isEmpty || _currentIndex == -1) return;
    final m = _matches[_currentIndex];
    final replacement = _replaceController.text;
    final full = widget.controller.text;
    final newText = full.replaceRange(m.start, m.end, replacement);
    widget.controller.text = newText;

    // recompute and try to keep index
    _recomputeMatches(keepIndexIfPossible: true);
    // after recompute, currentIndex already set and controller selection placed
  }

  void _replaceAll() {
    final patt = _findController.text;
    if (patt.isEmpty) return;
    final reg = _makeRegex(patt);
    final replaced = widget.controller.text.replaceAll(reg, _replaceController.text);
    widget.controller.text = replaced;
    _recomputeMatches(keepIndexIfPossible: false);
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
    final current = (_currentIndex == -1) ? 0 : (_currentIndex + 1);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  decoration: const InputDecoration(labelText: 'Find'),
                  onChanged: (_) => _recomputeMatches(),
                  onSubmitted: (_) => _recomputeMatches(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _prev, child: const Text('Prev')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _next, child: const Text('Next')),
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
              Checkbox(value: _caseSensitive, onChanged: (v) => setState(() { _caseSensitive = v ?? false; _recomputeMatches(); })),
              const Text('Case sensitive'),
              const SizedBox(width: 16),
              Checkbox(value: _wholeWord, onChanged: (v) => setState(() { _wholeWord = v ?? false; _recomputeMatches(); })),
              const Text('Whole word'),
              const Spacer(),
              ElevatedButton(onPressed: _replaceCurrentAndNext, child: const Text('Replace')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _replaceAll, child: const Text('Replace all')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  // return current match range if exists, so editor can scroll to it one last time
                  TextRange? ret;
                  if (_currentIndex >= 0 && _currentIndex < _matches.length) {
                    final m = _matches[_currentIndex];
                    ret = TextRange(start: m.start, end: m.end);
                  }
                  Navigator.of(context).pop(SearchReplaceResult(jumpTo: ret));
                },
                child: const Text('Close'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
