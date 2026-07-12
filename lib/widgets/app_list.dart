import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import '../vpn_controller.dart';

class AppListWidget extends StatefulWidget {
  final VpnController controller;
  const AppListWidget({super.key, required this.controller});

  @override
  State<AppListWidget> createState() => _AppListWidgetState();
}

class _AppListWidgetState extends State<AppListWidget> {
  List<Application>? apps;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    final list = await InstalledApps.getInstalledApps(true, true);
    setState(() => apps = list);
  }

  @override
  Widget build(BuildContext context) {
    if (apps == null) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      itemCount: apps!.length,
      itemBuilder: (context, i) {
        final a = apps![i];
        return ListTile(
          leading: a.icon == null ? null : Image.memory(a.icon!),
          title: Text(a.appName ?? a.packageName ?? 'Unknown'),
          subtitle: Text(a.packageName ?? ''),
          onLongPress: () async {
            final ok = await widget.controller.addAllowedApp(a.packageName ?? '');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Added to VPN' : 'Failed')));
          },
        );
      },
    );
  }
}
