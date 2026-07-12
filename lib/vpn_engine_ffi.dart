import 'dart:ffi';
import 'dart:convert';
import 'package:ffi/ffi.dart';

final DynamicLibrary _lib = DynamicLibrary.process();

typedef _c_StartEngine = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _dart_StartEngine = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _c_StopEngine = Int32 Function();
typedef _dart_StopEngine = int Function();

typedef _c_GetStatusJSON = Pointer<Utf8> Function();
typedef _dart_GetStatusJSON = Pointer<Utf8> Function();

typedef _c_FreeCString = Void Function(Pointer<Utf8>);
typedef _dart_FreeCString = void Function(Pointer<Utf8>);

final _startEngine = _lib.lookupFunction<_c_StartEngine, _dart_StartEngine>('StartEngine');
final _stopEngine = _lib.lookupFunction<_c_StopEngine, _dart_StopEngine>('StopEngine');
final _getStatusJSON = _lib.lookupFunction<_c_GetStatusJSON, _dart_GetStatusJSON>('GetStatusJSON');
final _freeCString = _lib.lookupFunction<_c_FreeCString, _dart_FreeCString>('FreeCString');

int startEngine(String pairingHash, String role, String preshared) {
  final pp = pairingHash.toNativeUtf8();
  final pr = role.toNativeUtf8();
  final ps = preshared.toNativeUtf8();
  final r = _startEngine(pp, pr, ps);
  calloc.free(pp);
  calloc.free(pr);
  calloc.free(ps);
  return r;
}

int stopEngine() => _stopEngine();

Map<String, dynamic> getStatus() {
  final p = _getStatusJSON();
  if (p == nullptr) return {"state": "UNKNOWN"};
  final s = p.toDartString();
  _freeCString(p);
  try {
    return json.decode(s) as Map<String, dynamic>;
  } catch (e) {
    return {"state": "UNKNOWN", "raw": s};
  }
}
