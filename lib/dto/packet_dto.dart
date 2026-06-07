
import 'dart:convert';
import 'dart:typed_data';

class Packet {
  final String? command;
  final String? success;
  final String? failure;

  Packet({
    required this.command,
    required this.success,
    required this.failure,
  });

  factory Packet.fromMap(Map<String, dynamic> map) {
    return Packet(
      command: map['command'].toString(),
      success: map['success'].toString(),
      failure: map['failure'].toString(),
    );
  }

  factory Packet.fromBytes(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    return Packet.fromMap(map);
  }

  Uint8List toBytes() {
    final jsonString = jsonEncode(toMap());
    return Uint8List.fromList(utf8.encode(jsonString));
  }
  
  Map<String, dynamic> toMap() {
    return {
      'command': command,
      'success': success,
      'failure': failure,
    };
  }
}