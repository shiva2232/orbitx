import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PowerPresentPage extends StatefulWidget {
  const PowerPresentPage({super.key});

  @override
  State<PowerPresentPage> createState() => _PowerPresentPageState();
}

class _PowerPresentPageState extends State<PowerPresentPage> {
  final TextEditingController _urlController =
      TextEditingController(text: 'https://example.com');
  final bool _isLoading = true;
  MethodChannel? _viewChannel;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final url = Uri.tryParse(text)?.hasScheme == true ? text : 'https://$text';
    _viewChannel?.invokeMethod('loadUrl', {'url': url});
    FocusScope.of(context).unfocus();
  }

  void _sendGesture(String action, Offset position, Size size) {
    final normalizedX = position.dx / size.width;
    final normalizedY = position.dy / size.height;
    _viewChannel?.invokeMethod('gesture', {
      'action': action,
      'x': normalizedX.clamp(0.0, 1.0),
      'y': normalizedY.clamp(0.0, 1.0),
    });
  }

  void _onPlatformViewCreated(int id) {
    _viewChannel = MethodChannel('power_present_webview_$id');
    _viewChannel!.invokeMethod('setInitialUrl', {
      'url': _urlController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Power Present'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _viewChannel?.invokeMethod('reload'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'Enter URL',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _loadUrl(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loadUrl,
                  child: const Text('Go'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 3,
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (Platform.isAndroid)
                  AndroidView(
                    viewType: 'power_present_webview',
                    onPlatformViewCreated: _onPlatformViewCreated,
                    creationParams: {
                      'url': _urlController.text,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                else
                  const Center(
                    child: Text('Power Present is supported on Android only.'),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) {
                    final box = context.findRenderObject() as RenderBox;
                    _sendGesture('tapDown', details.localPosition, box.size);
                  },
                  onPanUpdate: (details) {
                    final box = context.findRenderObject() as RenderBox;
                    _sendGesture('panUpdate', details.localPosition, box.size);
                  },
                  onPanEnd: (_) {
                    _viewChannel?.invokeMethod('gesture', {
                      'action': 'panEnd',
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
