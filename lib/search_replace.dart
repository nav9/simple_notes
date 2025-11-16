// lib/search_replace.dart
import 'package:flutter/material.dart';
import 'dart:core';

class SearchReplaceSheet extends StatefulWidget {
  final TextEditingController controller;
  SearchReplaceSheet({required this.controller});

  @override
  _SearchReplaceSheetState createState() => _SearchReplaceSheetState();
}

class _SearchReplaceSheetState extends State<SearchReplaceSheet> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  bool _caseSensitive = false;
  bool _wholeWord = false;
  int _lastFoundIndex = -1;

  RegExp _makeRegex(String pattern) {
    if (pattern.isEmpty) return RegExp('');
    final escaped = RegExp.escape(pattern);
    final expr = _wholeWord ? r'\b' + escaped + r'\b' : escaped;
    return RegExp(expr, caseSensitive: _caseSensitive);
  }

  void _findNext() {
    final text = widget.controller.text;
    final pattern = _findController.text;
    if (pattern.isEmpty) return;
    final reg = _makeRegex(pattern);
    final start = widget.controller.selection.end >= 0 ? widget.controller.selection.end : 0;
    final match = reg.firstMatch(text.substring(start));
    if (match != null) {
      final begin = start + match.start;
      final end = start + match.end;
      widget.controller.selection = TextSelection(baseOffset: begin, extentOffset: end);
      _lastFoundIndex = begin;
    } else {
      // try from start
      final match2 = reg.firstMatch(text);
      if (match2 != null) {
        widget.controller.selection = TextSelection(baseOffset: match2.start, extentOffset: match2.end);
        _lastFoundIndex = match2.start;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matches found')));
      }
    }
  }

  void _findPrev() {
    final text = widget.controller.text;
    final pattern = _findController.text;
    if (pattern.isEmpty) return;
    final reg = _makeRegex(pattern);
    final cursor = widget.controller.selection.start;
    // search all matches and find last before cursor
    final matches = reg.allMatches(text).toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matches found')));
      return;
    }
    Match? prev;
    for (final m in matches) {
      if (m.start < cursor) prev = m;
    }
    prev ??= matches.last; // wrap
    widget.controller.selection = TextSelection(baseOffset: prev.start, extentOffset: prev.end);
    _lastFoundIndex = prev.start;
  }

  void _replaceOne() {
    final sel = widget.controller.selection;
    final findPattern = _findController.text;
    if (findPattern.isEmpty) return;
    final reg = _makeRegex(findPattern);
    final selectedText = sel.textInside(widget.controller.text);
    if (reg.hasMatch(selectedText)) {
      final replaced = selectedText.replaceFirst(reg, _replaceController.text);
      final newText = widget.controller.text.replaceRange(sel.start, sel.end, replaced);
      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(offset: sel.start + replaced.length);
    } else {
      _findNext();
    }
  }

  void _replaceAll() {
    final text = widget.controller.text;
    final pattern = _findController.text;
    if (pattern.isEmpty) return;
    final reg = _makeRegex(pattern);
    final replaced = text.replaceAll(reg, _replaceController.text);
    widget.controller.text = replaced;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All occurrences replaced')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: _findController, decoration: const InputDecoration(labelText: 'Find'))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _findPrev, child: const Text('Prev')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _findNext, child: const Text('Next')),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _replaceController, decoration: const InputDecoration(labelText: 'Replace with')),
          Row(children: [
            Checkbox(value: _caseSensitive, onChanged: (v) => setState(() => _caseSensitive = v ?? false)),
            const Text('Case sensitive'),
            const SizedBox(width: 16),
            Checkbox(value: _wholeWord, onChanged: (v) => setState(() => _wholeWord = v ?? false)),
            const Text('Whole word'),
            const Spacer(),
            ElevatedButton(onPressed: _replaceOne, child: const Text('Replace')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _replaceAll, child: const Text('Replace all')),
          ]),
        ]),
      ),
    );
  }
}
