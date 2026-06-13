import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:orbitx/firebase_options.dart';
import 'package:orbitx/screens/apps_screen.dart';
import 'dart:io';

import 'package:orbitx/screens/map_screen.dart';
import 'package:orbitx/screens/script_screen.dart';
import 'package:orbitx/screens/terminal_screen.dart';
import 'package:orbitx/services/action_service.dart';
import 'package:orbitx/services/socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  WidgetsFlutterBinding.ensureInitialized();
  //   SystemChrome.setEnabledSystemUIMode(
  //   SystemUiMode.edgeToEdge,
  // );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbit X',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Orbit X'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  List<AppInfo> apps = [];
  StreamSubscription<Uint8List>? _subs;

  PageController pageController = PageController(initialPage: 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PopScope(
        canPop: false,
        child: PageView(
          controller: pageController,
          children: [
            Container(color: Colors.black, child: MapView()),
            Container(
              color: Colors.black,
              child: AppsScreen(apps: apps),
            ),
            Container(color: Colors.black, child: ScriptPage()),
            Container(color: Colors.black, child: Xterm()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final result = Process.run('termux-battery-status', []);
          result.then((value) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(value.stdout)));
            }
          });
          result.catchError((error) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.toString())));
            }
          });
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    service.listening.listen((on) {
      debugPrint("executing");
      if (on) {
        _subs = service.listen((packet) {
          debugPrint(packet.toString());
          if (packet.output != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  packet.output ?? '<Empty Response>',
                  style: const TextStyle(color: Colors.white),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          }
          String str = "";
          if (packet.success != null && packet.success != '') {
            str = packet.success!.split(" ")[0].trim() == "snd"
                ? "${packet.success!}::::"
                : packet.success ?? '';
          } else if (packet.failure != null && packet.failure != '') {
            str = packet.failure!.split(" ")[0].trim() == "snd"
                ? "${packet.failure!}::::"
                : packet.failure ?? '';
          }
          if (str != '') {
            ActionService.start(str, context);
          }
        });
      } else {
        if (_subs != null) {
          _subs!.cancel();
        }
      }
    });
    InstalledApps.getInstalledApps(
      excludeNonLaunchableApps: true,
      excludeSystemApps: false,
      withIcon: true,
    ).then((apps) {
      setState(() {
        this.apps = apps;
      });
    });
  }

  @override
  void dispose() {
    service.destroy();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }
}
