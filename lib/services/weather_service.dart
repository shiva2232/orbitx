import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

class WeatherService {
  static Future<Map<String, dynamic>> getWeather(
      String city) async {
    final response = await http.get(
      Uri.parse(
        "https://wttr.in/$city?format=j1",
      ),
    );

    return jsonDecode(response.body);
  }
  static Future<Map<String, dynamic>> getWeatherPoint(GeoPoint point) async {
    debugPrint("https://wttr.in/${point.latitude},${point.longitude}?format=j1\n\n");
    final response = await http.get(
      Uri.parse(
        "https://wttr.in/${point.latitude},${point.longitude}?format=j1",
      ),
    );

    return jsonDecode(response.body);
  }
}