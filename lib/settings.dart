import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Box settingsBox;

  @override
  void initState() {
    super.initState();
    settingsBox = Hive.box('settings');
  }

  Future<void> _pickFolder(String key, String title) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: title,
    );
    if (dir != null) {
      settingsBox.put(key, dir);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = settingsBox.get('themeMode', defaultValue: 'system');
    final exportDir = settingsBox.get('exportDir');
    final importDir = settingsBox.get('importDir');
    final algo =
        settingsBox.get('encryptionAlgo', defaultValue: 'aes256');

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Appearance',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          RadioListTile(
            title: const Text('System default'),
            value: 'system',
            groupValue: themeMode,
            onChanged: (v) {
              settingsBox.put('themeMode', v);
              setState(() {});
            },
          ),
          RadioListTile(
            title: const Text('Light'),
            value: 'light',
            groupValue: themeMode,
            onChanged: (v) {
              settingsBox.put('themeMode', v);
              setState(() {});
            },
          ),
          RadioListTile(
            title: const Text('Dark'),
            value: 'dark',
            groupValue: themeMode,
            onChanged: (v) {
              settingsBox.put('themeMode', v);
              setState(() {});
            },
          ),
          const Divider(),

          const ListTile(
            title: Text('Storage',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Export folder'),
            subtitle: Text(exportDir ?? 'Not set'),
            trailing: const Icon(Icons.edit),
            onTap: () =>
                _pickFolder('exportDir', 'Select export folder'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Import folder'),
            subtitle: Text(importDir ?? 'Not set'),
            trailing: const Icon(Icons.edit),
            onTap: () =>
                _pickFolder('importDir', 'Select import folder'),
          ),
          const Divider(),

          const ListTile(
            title: Text('Encryption',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
ListTile(
  leading: const Icon(Icons.security),
  title: const Text('Encryption algorithm'),
  trailing: DropdownButton<String>(
    value: algo,
    underline: const SizedBox(), // removes ugly underline in ListTile
    items: const [
      DropdownMenuItem(
        value: 'aes256',
        child: Text('AES-256'),
      ),
      DropdownMenuItem(
        value: 'fernet',
        child: Text('Fernet'),
      ),
    ],
    onChanged: (v) {
      if (v == null) return;
      settingsBox.put('encryptionAlgo', v);
      setState(() {});
    },
  ),
),

        ],
      ),
    );
  }
}
