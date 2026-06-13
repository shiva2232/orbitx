import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orbitx/helper/database.dart';
import 'package:orbitx/services/action_service.dart';
import 'package:orbitx/services/socket_service.dart';

class ScriptPage extends StatefulWidget {
  const ScriptPage({super.key});

  @override
  State<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends State<ScriptPage> {
  List<Map<String, dynamic>> _scripts = List.empty(growable: true);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _scripts.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsetsGeometry.all(10.0),
                child: StreamBuilder<bool>(
                  stream: service.listening,
                  builder: (context, snapshot) {
                    return Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: snapshot.hasData
                            ? snapshot.data!
                                  ? Colors.green
                                  : Colors.red
                            : Colors.yellow,
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        if (index == _scripts.length + 1) {
          return ListTile(
            leading: const Icon(Icons.add),
            title: const Text(
              'Add Script',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  final TextEditingController commandController =
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
                          final String command = commandController.text.trim();
                          if (command.isNotEmpty) {
                            DatabaseHelper.database.then((db) {
                              db.insert('scripts', {'command': command}).then((
                                _,
                              ) {
                                if (mounted) {
                                  setState(() {
                                    _scripts.add({'command': command});
                                  });
                                }
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
          );
        }

        final data = _scripts[index - 1];
        return ListTile(
          key: ValueKey(data['id'] ?? data['command']),
          leading: const Icon(Icons.code),
          title: Text(
            data['command'],
            style: const TextStyle(color: Colors.white),
          ),
          onTap: () async {
            final ScaffoldMessengerState scaffoldMessenger =
                ScaffoldMessenger.of(context);
            final bool status = await ActionService.start(data['command'], context);
            if (!mounted) return;
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text(
                  status ? 'success' : 'failed',
                  style: const TextStyle(color: Colors.white),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
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
                        db
                            .delete(
                              'scripts',
                              where: 'id = ?',
                              whereArgs: [data['id']],
                            )
                            .then((_) {
                              if (mounted) {
                                setState(() {
                                  _scripts.removeWhere(
                                    (script) => script['id'] == data['id'],
                                  );
                                });
                              }
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
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    // Load scripts from a source (e.g., local storage, database, etc.)
    DatabaseHelper.database.then((db) {
      // Fetch scripts from the database and update the UI
      db.query('scripts').then((scripts) {
        if (!mounted) return;
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
