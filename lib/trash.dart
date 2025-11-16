// lib/trash.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class TrashScreen extends StatefulWidget {
  @override
  _TrashScreenState createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Box<Map> _notesBox = Hive.box<Map>('notesBox');
  final Map<dynamic, bool> _selected = {};

  List<dynamic> _trashedKeys() {
    final res = <dynamic>[];
    for (int i = 0; i < _notesBox.length; i++) {
      final key = _notesBox.keyAt(i);
      final n = _notesBox.getAt(i)!;
      final isTrashed = n['isTrashed'] ?? false;
      if (isTrashed) res.add(key);
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
    for (final k in keys) {
      await _notesBox.delete(k);
      _selected.remove(k);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keys = _trashedKeys();
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
          final keys = _trashedKeys();
          if (keys.isEmpty) return const Center(child: Text('Trash is empty.'));
          return ListView.builder(
            itemCount: keys.length,
            itemBuilder: (context, idx) {
              final key = keys[idx];
              final note = box.get(key)!;
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
