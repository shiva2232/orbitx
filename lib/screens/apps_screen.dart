import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

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
    super.build(context); // Important!

    return GridView.count(
      crossAxisCount: MediaQuery.of(context).orientation == Orientation.landscape ? 10 : 5,
      children: List.generate(widget.apps.length, (index) {
        return Column(
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
                widget.apps[index].icon!,
                fit: BoxFit.contain,
                width: 32,
                height: 32,
              ),
              label: Text(''),
              onPressed: () {
                InstalledApps.startApp(widget.apps[index].packageName);
              },
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(widget.apps[index].name),
                    content: Text('Package: ${widget.apps[index].packageName}'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
            Text(widget.apps[index].name, style: TextStyle(fontSize: 10, color: Colors.white, overflow: TextOverflow.ellipsis, ), textAlign: TextAlign.center,),
          ],
        );
      }),
    );
  }
}
