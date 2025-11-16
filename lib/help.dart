// lib/help.dart
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  final List<Map<String, String>> items = [
    {'icon': 'add', 'explain': 'Add a new note'},
    {'icon': 'delete', 'explain': 'Delete (moves to Trash; use Undo to restore). No confirmation.'},
    {'icon': 'lock', 'explain': 'Encrypt all decrypted notes (clears session passwords)'},
    {'icon': 'download_outlined', 'explain': 'Export all notes to app documents folder'},
    {'icon': 'present_to_all', 'explain': 'Import note(s) from .txt files'},
    {'icon': 'access_time', 'explain': 'Insert current time into note (enabled when editing)'},
    {'icon': 'copy', 'explain': 'Copy note contents to clipboard'},
    {'icon': 'enhanced_encryption', 'explain': 'Encrypt / Decrypt the current note. Encrypted content remains unreadable unless decrypted with password.'},
    {'icon': 'system_update_alt', 'explain': 'Export current note to a file'},
    {'icon': 'save', 'explain': 'Save note (when editing). If a password is stored in session, saving will persist encrypted content on disk but keep UI plaintext until re-encrypted or app restart.'},
  ];

  IconData _iconFromName(String name) {
    switch (name) {
      case 'add':
        return Icons.add;
      case 'delete':
        return Icons.delete;
      case 'lock':
        return Icons.lock;
      case 'download_outlined':
        return Icons.download_outlined;
      case 'present_to_all':
        return Icons.present_to_all;
      case 'access_time':
        return Icons.access_time;
      case 'copy':
        return Icons.copy;
      case 'enhanced_encryption':
        return Icons.enhanced_encryption;
      case 'system_update_alt':
        return Icons.system_update_alt;
      case 'save':
        return Icons.save;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return ListTile(
            leading: Icon(_iconFromName(it['icon']!)),
            title: Text(it['icon']!),
            subtitle: Text(it['explain']!),
          );
        },
      ),
    );
  }
}
