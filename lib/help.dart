// lib/help.dart
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  final List<Map<String, String>> items = [
    {'icon': 'New note', 'explain': 'Create a new note'},
    {'icon': 'Move to trash', 'explain': 'Move selected notes to Trash. Use the restore or permanently delete options from the Trash page.'},
    {'icon': 'Encrypt all', 'explain': 'Encrypt all notes that are currently in temporary decrypted state (also clears session passwords). This is an emergency button to protect the decrypted notes quickly.'},
    {'icon': 'Merge', 'explain': 'Merge selected notes into a single note. Encrypted notes will prompt for passwords as needed. Notes are merged in their current order, with each note’s title followed by its contents.'},    
    {'icon': 'Export to disk', 'explain': 'Export notes to disk (if any notes are selected only those notes will be exported; otherwise all notes will be exported to disk). . In Android this would usually be in the folder `Android/com.simple_notes/`. In Linux it would usually be in the `~/Documents/` folder. Each note will be a text file with the note title being the filename.'},
    {'icon': 'Import from disk', 'explain': 'Import one or more notes from .txt files. The notes may be in encrypted form (in a format recognized by Simple Notes) or plain text.'},
    {'icon': 'Insert time', 'explain': 'Insert current time into note at the cursor position (enabled when editing)'},
    {'icon': 'Copy to clipboard', 'explain': 'Copy note contents to clipboard'},
    {'icon': 'Duplicate', 'explain': 'Duplicate the selected note(s)'},
    {'icon': 'Encrypt/Decrypt', 'explain': 'Encrypt or decrypt the current note.'},
    {'icon': 'Save', 'explain': 'Save note to the Simple Notes Hive database. Ctrl+S also saves on Linux.'},
    {'icon': 'Search', 'explain': 'Find & Replace: Ctrl+F to open search on Linux.'},
  ];

  IconData _iconFromName(String name) {
    switch (name) {
      case 'New note':
        return Icons.add;
      case 'Move to trash':
        return Icons.delete;
      case 'Merge':
        return Icons.merge_type;        
      case 'Encrypt all':
        return Icons.lock;
      case 'Export to disk':
        return Icons.download_outlined;
      case 'Import from disk':
        return Icons.file_upload;
      case 'Insert time':
        return Icons.access_time;
      case 'Copy to clipboard':
        return Icons.copy;
      case 'Duplicate':
        return Icons.control_point_duplicate;
      case 'Encrypt/Decrypt':
        return Icons.enhanced_encryption;
      case 'Save':
        return Icons.save;
      case 'Search':
        return Icons.search;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help'),),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return ListTile(leading: Icon(_iconFromName(it['icon']!)), title: Text(it['icon']!), subtitle: Text(it['explain']!),);
        },
      ),
    );
  }
}
