// lib/password_dialog.dart
import 'package:flutter/material.dart';
import 'session_manager.dart';
import 'package:flutter/services.dart';

Future<String?> showPasswordDialog(BuildContext context, String title, bool allowPrefill) {
  final controller = TextEditingController();
  final session = SessionManager();
  if (allowPrefill && session.sessionPassword != null) controller.text = session.sessionPassword!;
  return showDialog<String>(
    context: context,
    builder: (context) {
      return _PasswordAlert(controller: controller, title: title);
    },
  );
}

class _PasswordAlert extends StatelessWidget {
  final TextEditingController controller;
  final String title;
  const _PasswordAlert({required this.controller, required this.title});

  void _submit(BuildContext context) {
    Navigator.of(context).pop(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'Password'),
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => _submit(context), // ENTER key will submit
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => _submit(context), child: const Text('OK')),
      ],
    );
  }
}
