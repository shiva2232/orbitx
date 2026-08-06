import 'package:flutter/material.dart';
import 'package:orbitx/screens/scanner_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/v4.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextEditingController uuidController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xFF191C1E),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.question_mark_rounded,
              color: Color(0xFF191C1E),
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: Align(
        alignment: AlignmentGeometry.center,
        child: Container(
          width: MediaQuery.of(context).size.shortestSide * 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: TextField(
                  controller: uuidController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'UUID',
                    prefixIcon: const Icon(Icons.fingerprint, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () {
                        setState(() {
                          uuidController.text = Uuid().v4();
                        });
                      },
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  "Generate UUID",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 230, 228, 228),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: uuidController.text,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  children: const [
                    Expanded(
                      child: Divider(thickness: 1, color: Color(0xFFD5E4F8)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(thickness: 1, color: Color(0xFFD5E4F8)),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => ScannerView(),
                                  ),
                                );
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.shortestSide/8,
                    vertical: 15,
                  ),
                ),
                child: Text("Pair"),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    "Scan the QR code to connect to the device",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 20),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    fixedSize: Size(
                      MediaQuery.of(context).size.shortestSide * 0.9,
                      50,
                    ),
                  ),
                  onPressed: () {
                    showConfirmationDialog(context).then((confirmed) {
                      if (confirmed == true) {
                        _setUuid(uuidController.text);
                      } else {
                        // User canceled, do nothing
                      }
                    });
                  },
                  child: Text(
                    "Save & Continue",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setUuid(String uid) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.setString('uuid', uid);
  }

  Future<void> _loadUuid() async {
    final sharedPreferences = await SharedPreferences.getInstance();

    final storedUuid = sharedPreferences.getString('uuid');

    if (storedUuid != null) {
      if (!mounted) return;
      setState(() {
        uuidController.text = storedUuid;
      });
    } else {
      final uid = const Uuid().v4();
      await sharedPreferences.setString('uuid', uid);

      if (!mounted) return;
      setState(() {
        uuidController.text = uid;
      });
    }
  }

  initState() {
    super.initState();
    _loadUuid();
  }

  Future<bool?> showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Are you sure?'),
          content: const Text('This will disconnect all connected devices'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }
}
