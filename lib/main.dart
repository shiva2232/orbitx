import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:orbitx/firebase_options.dart';
import 'package:orbitx/helper/automation_engine.dart';
import 'package:orbitx/helper/database.dart';
import 'package:orbitx/helper/schedule_helper.dart';
import 'package:orbitx/helper/variable_context.dart';
import 'package:orbitx/models/automation_model.dart';
import 'package:orbitx/screens/apps_screen.dart';

import 'package:orbitx/screens/map_screen.dart';
import 'package:orbitx/screens/script_screen.dart';
import 'package:orbitx/screens/terminal_screen.dart';
import 'package:orbitx/screens/utils_screen.dart';
import 'package:orbitx/screens/weather_screen.dart';
import 'package:orbitx/services/action_service.dart';
import 'package:orbitx/services/socket_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Orbit X",
        content: "SMART MODE is On",
      );
      service.on("stopService").listen((event) {
        service.stopSelf();
      });
    }
  });
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final instance = DatabaseHelper.instance;
    await instance.initialize();
    final rules = await instance.loadAll();

    final now = DateTime.now();
    for (final rule in rules) {
      if (ScheduleEvaluator.shouldRunNow(rule, now)) {
        print("Run automation: ${rule.name}");

        await AutomationEngine.run(rule, AutomationContext({}));
      }
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      foregroundServiceNotificationId: 100,
      initialNotificationTitle: 'OrbitX',
      initialNotificationContent: 'Running',
    ),
    iosConfiguration: IosConfiguration(),
  );

  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  Workmanager().registerPeriodicTask(
    "automation-engine",
    "automation-engine",
    frequency: const Duration(minutes: 15),
  );
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
  double steps = 0;
  ScrollController scrollController = ScrollController();
  @override
  Widget build(BuildContext context) {
  final itemKeys = List.generate(apps.length, (_) => GlobalKey());
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
            Container(
              color: Colors.green,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: scrollController,
                    child: Row(
                      children: apps.asMap().entries
                          .map(
                            (app) => Column(
                              key: itemKeys[app.key],
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
                                    app.value.icon!,
                                    fit: BoxFit.contain,
                                    width: 32,
                                    height: 32,
                                  ),
                                  label: Text(''),
                                  onPressed: () {
                                    InstalledApps.startApp(app.value.packageName);
                                  },
                                  onLongPress: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(app.value.name),
                                        content: Text(
                                          'Package: ${app.value.packageName}',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                Text(
                                  app.value.name,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  SingleChildScrollView(
                    child: Slider(
                      value: steps,
                      label: String.fromCharCode(96 + steps.round()),
                      onChanged: (step) {
                        setState(() {
                          steps = step;
                        });
                        if (step == 0) {
                          scrollController.animateTo(
                            0,
                            duration: Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                          );
                        } else {
                          final int index = apps.indexWhere(
                            (app) => app.name.toLowerCase().startsWith(
                              String.fromCharCode(96 + step.round()),
                            ),
                          );
                          debugPrint(index.toString());
                          if (index != -1) {
                            scrollController.animateTo(
                              index * (itemKeys.first.currentContext?.findRenderObject() as RenderBox).size.width,
                              duration: Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        }
                      },
                      min: 0,
                      max: 26,
                      divisions: 27,
                    ),
                  ),
                ],
              ),
            ),
            Container(color: Colors.black, child: ScriptPage()),
            WeatherScreen(),
            UtilPage(),
            Container(color: Colors.black, child: Xterm()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          Permission.notification.isGranted.then((value) {
            if (value) {
              final service = FlutterBackgroundService();
              service.isRunning().then((isRunning) {
                if (!isRunning) {
                  service.startService();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("SMART turned On")));
                } else {
                  service.invoke("stopService");
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("SMART turned Off")));
                }
              });
            } else {
              Permission.notification.request();
            }
          });
        },
        mini: true,
        tooltip: 'Activate SMART',
        child: const Icon(Icons.auto_awesome),
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
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
