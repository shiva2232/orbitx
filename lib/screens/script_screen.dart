import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orbitx/helper/database.dart';

class ScriptPage extends StatefulWidget {
  const ScriptPage({super.key});

  @override
  State<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends State<ScriptPage> {
  List<Map<String, dynamic>> _scripts = List.empty(growable: true);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ..._scripts.map<Widget>(
          (data) => ListTile(
            leading: const Icon(Icons.code),
            title: Text(data['command'], style: const TextStyle(color: Colors.white)),
            onTap: () {
              List<String> parts = data['command'].toString().split(' ');
              var result = Process.run(parts[0], parts.sublist(1), runInShell: true);
              result.then(
                (value) => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(value.stdout, style: const TextStyle(color: Colors.white)))),
              );
              result.catchError((error) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString(), style: const TextStyle(color: Colors.white))));
              });
            },
            onLongPress: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(data['command']),
                  content: Text('Command: ${data['command']}'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    TextButton(
                      onPressed: () {
                        DatabaseHelper.database.then((db) {
                          db.delete('scripts', where: 'id = ?', whereArgs: [data['id']]).then((_) {
                            setState(() {
                              _scripts.removeWhere((script) => script['id'] == data['id']);
                            });
                          });
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add Script'),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) {
                TextEditingController commandController =
                    TextEditingController();
                return AlertDialog(
                  title: const Text('Add Script'),
                  content: TextField(
                    controller: commandController,
                    decoration: const InputDecoration(
                      hintText: 'Enter command',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        String command = commandController.text.trim();
                        if (command.isNotEmpty) {
                          DatabaseHelper.database.then((db) {
                            db.insert('scripts', {'command': command}).then((
                              _,
                            ) {
                              setState(() {
                                _scripts.add({'command': command});
                              });
                            });
                          });
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Add'),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Load scripts from a source (e.g., local storage, database, etc.)
    DatabaseHelper.database.then((db) {
      // Fetch scripts from the database and update the UI
      db.query('scripts').then((scripts) {
        // Update the state with the fetched scripts
        setState(() {
          _scripts = scripts;
        });
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    DatabaseHelper.database.then((db) {
      // db.close();
    });
  }
}
