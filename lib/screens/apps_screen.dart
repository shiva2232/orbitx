import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:orbitx/widgets/app_shortcut_tile.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, required this.apps});

  final List<AppInfo> apps;
  
  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            MediaQuery.of(context).orientation == Orientation.landscape ? 10 : 5,
      ),
      itemCount: widget.apps.length,
      itemBuilder: (context, index) {
        final app = widget.apps[index];

        return AppShortcutTile(
          app: app,
          onPressed: () {
            InstalledApps.startApp(app.packageName);
          },
          onLongPress: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(app.name),
                content: Text('Package: ${app.packageName}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
