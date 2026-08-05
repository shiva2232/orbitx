import 'dart:async';
import 'dart:ui';

// import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:orbitx/helper/automation_engine.dart';
import 'package:orbitx/helper/database.dart';
import 'package:orbitx/helper/frp_config.dart';
import 'package:orbitx/helper/schedule_helper.dart';
import 'package:orbitx/helper/variable_context.dart';
import 'package:orbitx/models/proxies_model.dart';
// import 'package:orbitx/screens/apps_screen.dart';

// import 'package:orbitx/screens/map_screen.dart';
// import 'package:orbitx/screens/script_screen.dart';
// import 'package:orbitx/screens/terminal_screen.dart';
// import 'package:orbitx/screens/utils_screen.dart';
// import 'package:orbitx/screens/weather_screen.dart';
import 'package:orbitx/services/action_service.dart';
import 'package:orbitx/services/frp_service.dart';
import 'package:orbitx/services/socket_service.dart';
import 'package:orbitx/utils/tcp_utils.dart';
import 'package:orbitx/vpn_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/validation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
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
  StreamSubscription<Map<String, dynamic>>? _vpnStatusSub;
  String? tunnelPeerIp;
  int? tunnelPeerPort;
  bool tunnelConnected = false;
  bool vpnEnabled = false;
  double width = 0.0;
  final PageController pageController = PageController(initialPage: 0);
  double steps = 0;
  final ScrollController scrollController = ScrollController();
  List<AppInfo> filtered = [];
  bool showLay = false;
  bool isMaster = false;
  bool isFrps = false;
  ProxyResponse locProxyResponse = ProxyResponse(proxies: []);
  ProxyResponse remProxyResponse = ProxyResponse(proxies: []);
  final List<InputItem> _items = [];
  bool isFrpc = false;

  String get currentRole => isMaster ? 'master' : 'slave';

  @override
  Widget build(BuildContext context) {
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
                          padding: EdgeInsets.all(5),
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
                                color: Color.from(
                                  alpha: 0.5,
                                  red: 0.1,
                                  green: 0.1,
                                  blue: 0.1,
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                ),
                                child: const Icon(
                                  Icons.swipe_right_alt_rounded,
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
                                // addOrRemoveVpn(app.packageName).then((val) {
                                //   ScaffoldMessenger.of(context).showSnackBar(
                                //     SnackBar(
                                //       content: Text(
                                //         val['result'] == true
                                //             ? '${val['isAdd'] == true ? 'Added' : 'Removed'} to VPN'
                                //             : 'Failed',
                                //       ),
                                //     ),
                                //   );
                                // });
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
                    ],
                  ),
                ),
                // Container(color: Colors.black, child: ScriptPage()),
                // WeatherScreen(),
                // Container(
                //   color: Colors.black,
                //   child: AppsScreen(apps: apps),
                // ),
                // Container(color: Colors.black, child: MapView()),
                // UtilPage(),
                // Container(color: Colors.black, child: Xterm()),
              ],
            ),
            if (showLay)
              Positioned(
                height: MediaQuery.of(context).size.shortestSide - 100,
                width: MediaQuery.of(context).size.shortestSide - 100,
                bottom: 70,
                right: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    // backgroundBlendMode: BlendMode.difference,
                  ),
                  child: ListView(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(isMaster ? 'Server' : 'Client'),
                                Switch(
                                  value: isMaster,
                                  onChanged: vpnEnabled
                                      ? null
                                      : (val) => {
                                          setState(() {
                                            isMaster = val;
                                          }),
                                        },
                                ),
                              ],
                            ),
                          ),
                          Center(
                            child: Column(
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      _setVpnEnabled(!vpnEnabled);
                                    },
                                    borderRadius: BorderRadius.circular(
                                      MediaQuery.of(context).size.shortestSide /
                                          1.5,
                                    ),
                                    child: Ink(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: vpnEnabled
                                                ? Colors.green
                                                : Colors
                                                      .blue, // Custom shadow color
                                            blurRadius:
                                                0, // Moves shadow slightly down (x, y)
                                          ),
                                        ],
                                      ),
                                      child: Container(
                                        width:
                                            MediaQuery.of(
                                              context,
                                            ).size.shortestSide /
                                            3,
                                        height:
                                            MediaQuery.of(
                                              context,
                                            ).size.shortestSide /
                                            3,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: vpnEnabled
                                                  ? Colors.green
                                                  : Colors.blue,
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.power_settings_new_sharp,
                                          color: vpnEnabled
                                              ? Colors.green
                                              : Colors.blue,
                                          size:
                                              MediaQuery.of(
                                                context,
                                              ).size.shortestSide /
                                              8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    tunnelConnected
                                        ? 'Connected: ${tunnelPeerIp ?? 'unknown'}:${tunnelPeerPort ?? 0}'
                                        : (vpnEnabled
                                              ? 'Waiting for tunnel...'
                                              : 'Tap switch to enable VPN'),
                                    style: TextStyle(
                                      backgroundColor: Colors.white.withAlpha(
                                        100,
                                      ),
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(
                                    MediaQuery.of(context).size.shortestSide /
                                        16,
                                  ),
                                  child: Card(
                                    color: Colors.white,
                                    shadowColor: Colors.grey,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        spacing: 20,
                                        children: [
                                          Column(
                                            children: [
                                              Text(
                                                "Virtual IP",
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              Text(
                                                isMaster
                                                    ? '10.0.0.1'
                                                    : '10.0.0.2',
                                                style: TextStyle(fontSize: 16),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            children: [
                                              Text(
                                                "Peer IP",
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              Text(
                                                isMaster
                                                    ? '10.0.0.2'
                                                    : '10.0.0.1',
                                                style: TextStyle(fontSize: 16),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                                // setState(() {
                                //   isMaster = true;
                                // });
                                // ScaffoldMessenger.of(context).showSnackBar(
                                //   const SnackBar(
                                //     content: Text('Role set to MASTER'),
                                //   ),
                                // );
                                return Future.value(false);
                              } else {
                                // setState(() {
                                //   isMaster = false;
                                // });
                                // ScaffoldMessenger.of(context).showSnackBar(
                                //   const SnackBar(
                                //     content: Text('Role set to SLAVE'),
                                //   ),
                                // );
                                return Future.value(false);
                              }
                            },
                            child: ListTile(
                              textColor: Colors.blue,
                              title: Text('SMART MODE'),
                              subtitle: Text(isMaster ? 'Server' : 'Client'),
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
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Allow local network(via frps)'),
                            Switch(
                              value: isFrps,
                              onChanged: !vpnEnabled
                                  ? null
                                  : (val) async {
                                      if (val) {
                                        debugPrint(
                                          FrpsConfig(
                                            authToken: "HRyz5HYfW9B7d6Z3",
                                            bindAddr:
                                                '0.0.0.0', // connect any network device.
                                            bindPort: 7000,
                                          ).toTomlString(),
                                        );
                                        await FrpService.startFrps(
                                          FrpsConfig(
                                            authToken: "HRyz5HYfW9B7d6Z3",
                                            bindAddr:
                                                '0.0.0.0', // connect any network device.
                                            bindPort: 7000,
                                          ).toTomlString(),
                                        );
                                      } else {
                                        await FrpService.stopFrpc();
                                        await FrpService.stopFrps();
                                        setState(() {
                                          isFrpc = false;
                                        });
                                      }
                                      setState(() {
                                        isFrps = val;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),

                      if (isFrps) ...[
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Add Proxy'),
                              IconButton(
                                icon: Icon(Icons.add),
                                onPressed: !vpnEnabled
                                    ? null
                                    : () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (ctx) => _AddItemBottomSheet(
                                            onItemAdded: (name, address, port, proxyType) async {
                                              final la = address.split(':')[0];
                                              final lp = int.parse(
                                                address.split(':')[1],
                                              );

                                              // Always stop existing frpc before starting with new config
                                              await FrpService.stopFrpc();

                                              final frpcConfig = FrpcConfig(
                                                authToken: "HRyz5HYfW9B7d6Z3",
                                                serverAddr: isMaster
                                                    ? '10.0.0.1'
                                                    : '10.0.0.2',
                                                serverPort: 7000,
                                                proxies: [
                                                  ..._items.map((e) {
                                                    if (e.address ==
                                                            address &&
                                                        e.port == port) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            "Port already in use.",
                                                          ),
                                                        ),
                                                      );
                                                      return null;
                                                    }
                                                    final la = e.address
                                                        .split(':')[0];
                                                    final lp = int.parse(
                                                      e.address.split(':')[1],
                                                    );
                                                    return FrpProxyConfig(
                                                      name: e.name,
                                                      type: e.type,
                                                      localIp: la,
                                                      localPort: lp,
                                                      remotePort: e.port,
                                                    );
                                                  }).whereType<FrpProxyConfig>(),
                                                  FrpProxyConfig(
                                                    name: name,
                                                    type: proxyType,
                                                    localIp: la,
                                                    localPort: lp,
                                                    remotePort: port,
                                                  ),
                                                ],
                                              ).toTomlString();

                                              debugPrint(frpcConfig);
                                              try {
                                                final result = await FrpService.startFrpc(frpcConfig);
                                                debugPrint("Started frpc: $result");

                                                final localResponse = await getTcpProxies(
                                                  isMaster ? '10.0.0.1' : '10.0.0.2',
                                                );

                                                if (mounted) {
                                                  setState(() {
                                                    isFrpc = true;
                                                    _items.insert(
                                                      0,
                                                      InputItem(
                                                        name: name,
                                                        address: address,
                                                        port: port,
                                                        type: proxyType,
                                                      ),
                                                    );
                                                    locProxyResponse = localResponse;
                                                  });
                                                }
                                              } catch (e) {
                                                debugPrint("Error starting frpc: $e");
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(e.toString())),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        );
                                      },
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Local network'),
                              IconButton(
                                onPressed: !vpnEnabled
                                    ? null
                                    : () {
                                        getTcpProxies(
                                          isMaster ? '10.0.0.1' : '10.0.0.2',
                                        ).then(
                                          (localResponse) => {
                                            if (mounted)
                                              {
                                                setState(() {
                                                  locProxyResponse =
                                                      localResponse;
                                                }),
                                              },
                                          },
                                        );
                                      },
                                icon: Icon(Icons.refresh),
                              ),
                            ],
                          ),
                        ),
                        ...locProxyResponse.proxies.map(
                          (lpr) => Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.call_made),
                              title: Text(
                                "${lpr.conf.name} -> ${lpr.conf.remotePort}(${lpr.status})",
                              ),
                              subtitle: Text(
                                "${lpr.name}${lpr.conf.type}(${lpr.lastCloseTime})",
                              ),
                              trailing: Text(lpr.curConns.toString()),
                            ),
                          ),
                        ),
                      ],
                      if (vpnEnabled) ...[
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Remote Network'),
                              IconButton(
                                onPressed: !vpnEnabled
                                    ? null
                                    : () {
                                        getTcpProxies(
                                          isMaster ? '10.0.0.2' : '10.0.0.1',
                                        ).then(
                                          (remoteResponse) => {
                                            if (mounted)
                                              {
                                                setState(() {
                                                  remProxyResponse =
                                                      remoteResponse;
                                                }),
                                              },
                                          },
                                        );
                                      },
                                icon: Icon(Icons.refresh),
                              ),
                            ],
                          ),
                        ),
                        ...remProxyResponse.proxies.map(
                          (lpr) => Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.call_received),
                              title: Text(
                                "${lpr.conf.name} -> ${lpr.conf.remotePort}(${lpr.status})",
                              ),
                              subtitle: Text(
                                "${lpr.name}${lpr.conf.type}(${lpr.lastCloseTime})",
                              ),
                              trailing: Text(lpr.curConns.toString()),
                            ),
                          ),
                        ),
                      ],
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
    _vpnStatusSub = controller.events.listen((event) {
      if (event['event'] == 'connected') {
        setState(() {
          tunnelConnected = true;
          tunnelPeerIp = event['peerIp'] as String?;
          tunnelPeerPort = event['peerPort'] as int?;
        });
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
    _vpnStatusSub?.cancel();
    _subs?.cancel();
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

  Future<String> _ensurePairingHash() async {
    if (kDebugMode) {
      return 'af9aa286-d101-47b8-b799-2fa16d660e83';
    }
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final String? value = clipboard?.text;
    debugPrint("Clipboard: $value");
    if (value != null && UuidValidation.isValidUUID(fromString: value)) {
      return value;
    }
    final pairingHash = const Uuid().v4();
    await Clipboard.setData(ClipboardData(text: pairingHash));
    return pairingHash;
  }

  Future<void> _setVpnEnabled(bool enabled) async {
    setState(() {
      vpnEnabled = enabled;
    });

    if (!enabled) {
      await controller.stopService();
      setState(() {
        tunnelConnected = false;
        tunnelPeerIp = null;
        tunnelPeerPort = null;
      });
      return;
    }

    final pairingHash = await _ensurePairingHash();
    final ok = await controller.requestPermissionAndStart(
      pairingHash,
      currentRole,
      'presharedSecret',
    );
    if (!ok) {
      debugPrint("ok is $ok");
      setState(() {
        vpnEnabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('VPN permission denied or failed to start'),
        ),
      );
      return;
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

// Bottom Sheet Widget Separation for clean architecture
class _AddItemBottomSheet extends StatefulWidget {
  final Future<void> Function(String, String, int, ProxyType) onItemAdded;

  const _AddItemBottomSheet({required this.onItemAdded});

  @override
  State<_AddItemBottomSheet> createState() => _AddItemBottomSheetState();
}

class _AddItemBottomSheetState extends State<_AddItemBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _portController = TextEditingController();
  ProxyType _selectedProxyType = ProxyType.tcp;
  final _nameController = TextEditingController();

  void _submitData() {
    if (_formKey.currentState!.validate()) {
      final enteredAddress = _addressController.text;
      final enteredName = _nameController.text;
      final enteredPort = int.parse(_portController.text);

      widget.onItemAdded(
        enteredName,
        enteredAddress,
        enteredPort,
        _selectedProxyType,
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Add New Entry',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Server Name',
                  prefixIcon: const Icon(Icons.label, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a server name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _addressController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: '192.168.0.44:8080',
                  prefixIcon: const Icon(Icons.link, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty ||
                      !value.contains(':')) {
                    return 'e.g., 192.168.0.44:8080';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Port',
                  prefixIcon: const Icon(Icons.tag, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                validator: (value) {
                  if (value == null ||
                      value.isEmpty ||
                      int.tryParse(value) == null) {
                    return 'Please enter a port number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ProxyType>(
                value: ProxyType.tcp,
                hint: const Text('Select Proxy Type'),
                items: ProxyType.values.map((ProxyType type) {
                  return DropdownMenuItem<ProxyType>(
                    value: type,
                    child: Text(type.toString().split('.').last.toUpperCase()),
                  );
                }).toList(),
                validator: (value) {
                  if (value == null) {
                    return 'Please select a proxy type';
                  }
                  return null;
                },
                onChanged: (ProxyType? newValue) {
                  setState(() {
                    _selectedProxyType = newValue!;
                  });
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _submitData,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                label: const Text(
                  'Add to List',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Data model to store our entries
class InputItem {
  final String name;
  final ProxyType type;
  final String address;
  final int port;

  InputItem({
    required this.name,
    required this.address,
    required this.port,
    required this.type,
  });
}
