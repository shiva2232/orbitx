import 'package:flutter/material.dart';
import '../utils/weather_utils.dart';

class ForecastTile extends StatelessWidget {
  final Map<String, dynamic> day;

  const ForecastTile({
    super.key,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final hourly = day["hourly"][4];

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              day["date"],
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
          ),

          Icon(
            WeatherUtils.weatherCodeIcon(
              hourly["weatherCode"],
            ),
            color: Colors.white,
          ),

          const SizedBox(width: 12),

          Text(
            "${day["mintempC"]}°",
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),

          const SizedBox(width: 8),

          Text(
            "${day["maxtempC"]}°",
            style: const TextStyle(
              color: Colors.white,
            ),
          ),

          const SizedBox(width: 8),

          Text(
            "${hourly["chanceofrain"]}%",
            style: const TextStyle(
              color: Colors.lightBlueAccent,
            ),
          ),
        ],
      ),
    );
  }
}