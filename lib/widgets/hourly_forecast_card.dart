import 'package:flutter/material.dart';
import '../utils/weather_utils.dart';

class HourlyForecastCard extends StatelessWidget {
  final Map<String, dynamic> hourly;

  const HourlyForecastCard({
    super.key,
    required this.hourly,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            WeatherUtils.formatTime(
              hourly["time"],
            ),
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),

          Icon(
            WeatherUtils.weatherCodeIcon(
              hourly["weatherCode"],
            ),
            color: Colors.white,
          ),

          Text(
            "${hourly["tempC"]}°",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),

          Text(
            "${hourly["chanceofrain"]}% Rain",
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}