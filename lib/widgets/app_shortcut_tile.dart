import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';

class AppShortcutTile extends StatefulWidget {
  const AppShortcutTile({
    super.key,
    required this.app,
    required this.onPressed,
    required this.onLongPress,
  });

  final AppInfo app;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  @override
  State<AppShortcutTile> createState() => _AppShortcutTileState();
}

class _AppShortcutTileState extends State<AppShortcutTile> {
  
  final GlobalKey _appItemKeys=GlobalKey();
  @override
  Widget build(BuildContext context) {
    return Column(
      key: _appItemKeys,
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            iconSize: 32,
            padding: EdgeInsets.zero,
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Image.memory(
            widget.app.icon!,
            fit: BoxFit.contain,
            width: 32,
            height: 32,
          ),
          label: const Text(''),
          onPressed: widget.onPressed,
          onLongPress: widget.onLongPress,
        ),
        Text(
          widget.app.name,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white,
            overflow: TextOverflow.ellipsis,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
