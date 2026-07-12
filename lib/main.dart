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
import 'package:orbitx/screens/apps_screen.dart';

import 'package:orbitx/screens/map_screen.dart';
import 'package:orbitx/screens/script_screen.dart';
import 'package:orbitx/screens/terminal_screen.dart';
import 'package:orbitx/screens/utils_screen.dart';
import 'package:orbitx/screens/weather_screen.dart';
import 'package:orbitx/services/action_service.dart';
import 'package:orbitx/services/socket_service.dart';
import 'package:orbitx/vpn_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/validation.dart';
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
  VpnController controller = VpnController();
  List<AppInfo> apps = [];
  StreamSubscription<Uint8List>? _subs;
  double width = 0.0;
  final PageController pageController = PageController(initialPage: 0);
  double steps = 0;
  final ScrollController scrollController = ScrollController();
  List<AppInfo> filtered = [];
  bool showLay = false;
  bool isMaster = false;

  String get currentRole => isMaster ? 'master' : 'slave';

  @override
  Widget build(BuildContext context) {
    void genHash() {
      Uuid uuid = Uuid();
      String pairingHash = uuid.v4();
      Clipboard.setData(ClipboardData(text: pairingHash));
      controller.requestPermissionAndStart(
        pairingHash,
        currentRole,
        "presharedSecret",
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Uid Copied to clipboard!!!")));
    }

    return Scaffold(
      extendBody: true,
      body: PopScope(
        canPop: false,
        child: Stack(
          children: [
            PageView(
              controller: pageController,
              children: [
                Container(
                  color: Colors.green,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        color: Color.from(
                          alpha: 0.5,
                          red: 0.0,
                          green: 0.5,
                          blue: 0.5,
                        ),
                        child: Padding(
                          padding: EdgeInsetsGeometry.all(5),
                          child: TextField(
                            onChanged: (value) {
                              setState(() {
                                filtered = apps
                                    .where(
                                      (app) => app.name.toLowerCase().contains(
                                        value.toLowerCase(),
                                      ),
                                    )
                                    .toList();
                              });
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          scrollDirection: Axis.vertical,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final app = filtered[index];
                            return Dismissible(
                              // 2. Assign a unique key matching the data object (Crucial for ListView performance)
                              key: Key(app.packageName),

                              // 3. Set the swipe direction
                              direction: DismissDirection.horizontal,

                              // Visual background when swiping right (e.g., Save/Archive)
                              background: Container(
                                color: Colors.green,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                ),
                                child: const Icon(
                                  Icons.archive,
                                  color: Colors.white,
                                ),
                              ),

                              // Visual background when swiping left (e.g., Delete)
                              secondaryBackground: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                ),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),

                              // 4. Handle confirmation logic (Optional: e.g., show an alert before deleting)
                              confirmDismiss: (direction) async {
                                if (direction == DismissDirection.endToStart) {
                                  // Return true to allow dismissal, false to cancel
                                  pageController.animateToPage(
                                    1,
                                    duration: Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                  );
                                  return false;
                                }
                                // Allow swipe right unconditionally
                                addOrRemoveVpn(app.packageName).then((val) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        val['result'] == true
                                            ? '${val['isAdd'] == true ? 'Added' : 'Removed'} to VPN'
                                            : 'Failed',
                                      ),
                                    ),
                                  );
                                });
                                return false;
                              },

                              // 5. Handle state changes when a swipe finishes
                              onDismissed: (direction) {
                                if (direction == DismissDirection.startToEnd) {
                                  // Handle swipe right action (e.g., archive)
                                } else if (direction ==
                                    DismissDirection.endToStart) {}
                              },

                              // The actual item content
                              child: Material(
                                color: Color.from(
                                  alpha: 0.5,
                                  red: 0.1,
                                  green: 0.1,
                                  blue: 0.1,
                                ),
                                child: ListTile(
                                  onTap: () {
                                    InstalledApps.startApp(app.packageName);
                                  },
                                  onLongPress: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(app.name),
                                        content: Text(
                                          'Package: ${app.packageName}',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Close'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              InstalledApps.uninstallApp(
                                                app.packageName,
                                              );
                                              Navigator.pop(context);
                                            },
                                            child: const Text('Uninstall'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  leading: Image.memory(
                                    app.icon!,
                                    fit: BoxFit.contain,
                                    width: 32,
                                    height: 32,
                                  ),
                                  subtitle: Text(app.packageName),
                                  title: Text(app.name),
                                  trailing: Text(app.versionName),
                                  tileColor: Color.fromARGB(122, 167, 167, 167),
                                  hoverColor: Color.fromARGB(134, 35, 53, 88),
                                  titleAlignment: ListTileTitleAlignment.center,
                                  style: ListTileStyle.list,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Slider(
                        value: steps,
                        label: String.fromCharCode(97 + steps.round()),
                        onChanged: (step) {
                          setState(() {
                            steps = step;
                          });
                          final int index = apps.indexWhere(
                            (app) => app.name.toLowerCase().startsWith(
                              String.fromCharCode(97 + step.round()),
                            ),
                          );
                          debugPrint(
                            "$index $index $step ${index * width} $width",
                          );
                          if (index != -1) {
                            scrollController.animateTo(
                              index * width,
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        min: 0,
                        max: 27,
                        divisions: 27,
                      ),
                    ],
                  ),
                ),
                Container(color: Colors.black, child: ScriptPage()),
                WeatherScreen(),
                Container(
                  color: Colors.black,
                  child: AppsScreen(apps: apps),
                ),
                Container(color: Colors.black, child: MapView()),
                UtilPage(),
                Container(color: Colors.black, child: Xterm()),
              ],
            ),
            if (showLay)
              Positioned(
                height: MediaQuery.of(context).size.shortestSide - 100,
                width: MediaQuery.of(context).size.shortestSide - 100,
                bottom: 100,
                right: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    backgroundBlendMode: BlendMode.softLight,
                  ),
                  child: ListView(
                    children: [
                      Material(
                        child: Ink(
                          decoration: BoxDecoration(
                            color: Colors.white, // Magenta background
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            textColor: Colors.blue,
                            title: Text('TUNNEL'),
                            onTap: () {
                              debugPrint("TUNNEL");
                              Clipboard.getData(Clipboard.kTextPlain).then((
                                value,
                              ) {
                                debugPrint("Clipboard: ${value?.text}");
                                if (value != null && value.text != null) {
                                  final pairingHash = value.text!;
                                  if (UuidValidation.isValidUUID(
                                    fromString: pairingHash,
                                  )) {
                                    controller.requestPermissionAndStart(
                                      pairingHash,
                                      currentRole,
                                      "presharedSecret",
                                    );
                                  } else {
                                    genHash();
                                  }
                                } else {
                                  genHash();
                                }
                              });
                            },
                            onLongPress: () {
                              debugPrint("TUNNEL");
                              Clipboard.getData(Clipboard.kTextPlain).then((
                                value,
                              ) {
                                debugPrint("Clipboard: ${value?.text}");
                                if (value != null && value.text != null) {
                                  final pairingHash = value.text!;
                                  if (UuidValidation.isValidUUID(
                                    fromString: pairingHash,
                                  )) {
                                    controller.requestPermissionAndStart(
                                      pairingHash,
                                      currentRole,
                                      "presharedSecret",
                                    );
                                  } else {
                                    genHash();
                                  }
                                } else {
                                  genHash();
                                }
                              });
                            },
                          ),
                        ),
                      ),
                      Material(
                        child: Ink(
                          decoration: BoxDecoration(
                            color: Colors.white, // Magenta background
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Dismissible(
                            key: Key('smart_mode'),
                            direction: DismissDirection.horizontal,
                            confirmDismiss: (direction) {
                              if (direction == DismissDirection.endToStart) {
                                setState(() {
                                  isMaster = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Role set to MASTER'),
                                  ),
                                );
                                return Future.value(false);
                              } else {
                                setState(() {
                                  isMaster = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Role set to SLAVE'),
                                  ),
                                );
                                return Future.value(false);
                              }
                            },
                            child: ListTile(
                              textColor: Colors.blue,
                              title: Text('SMART MODE'),
                              subtitle: Text(isMaster ? 'MASTER' : 'SLAVE'),
                              onTap: () {
                                Permission.notification.isGranted.then((value) {
                                  if (value) {
                                    final service = FlutterBackgroundService();
                                    service.isRunning().then((isRunning) {
                                      if (!isRunning) {
                                        service.startService();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text("SMART turned On"),
                                          ),
                                        );
                                      } else {
                                        service.invoke("stopService");
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text("SMART turned Off"),
                                          ),
                                        );
                                      }
                                    });
                                  } else {
                                    Permission.notification.request();
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      Material(
                        child: ListTile(
                          title: const Text('Device Role'),
                          subtitle: Text(currentRole.toUpperCase()),
                          trailing: Switch(
                            value: isMaster,
                            onChanged: (value) {
                              setState(() {
                                isMaster = value;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value ? 'Role set to MASTER' : 'Role set to SLAVE',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          setState(() {
            showLay = !showLay;
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
        filtered = apps;
      });
    });
  }

  @override
  void dispose() {
    service.destroy();
    WidgetsBinding.instance.removeObserver(this);
    pageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<Map<String, bool>> addOrRemoveVpn(String packageName) async {
    // load current state from controller
    final bool already = controller.isAllowed(packageName);
    bool ok = false;
    if (!already) {
      // add to VPN allowed apps
      ok = await controller.addAllowedApp(packageName);
    } else {
      // remove from VPN allowed apps
      ok = await controller.removeAllowedApp(packageName);
    }
    return {"result": ok, "isAdd": !already};
  }
}
