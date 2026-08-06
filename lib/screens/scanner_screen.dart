import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScannerView extends StatefulWidget {
  const ScannerView({super.key});

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
            _setUuid(barcodes.elementAt(0).displayValue!);
        },
      ),
    );
  }
  
  Future<void> _setUuid(String uid) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.setString('uuid', uid);
    if(mounted){
      Navigator.of(context).pop();
    }
  }
}