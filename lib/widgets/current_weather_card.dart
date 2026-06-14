import 'package:flutter/material.dart';
import '../dto/weather_dto.dart';
import '../utils/weather_utils.dart';

class CurrentWeatherCard extends StatelessWidget {
  final WeatherData weather;

  const CurrentWeatherCard({
    super.key,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(alpha: .15),
        ),
      ),
      child: Column(
        children: [
          Text(
            weather.city,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          Icon(
            WeatherUtils.weatherCodeIcon(
              weather.weatherCode,
            ),
            size: 70,
            color: Colors.white,
          ),

          const SizedBox(height: 12),

          Text(
            "${weather.temp}°",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 72,
              fontWeight: FontWeight.w300,
            ),
          ),

          Text(
            weather.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 24),

          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _info(Icons.water_drop, "Humidity",
                  "${weather.humidity}%"),

              _info(Icons.umbrella, "Rain",
                  "${weather.precipitation} mm"),

              _info(Icons.air, "Wind",
                  "${weather.windSpeed} km/h"),

              _info(Icons.thermostat, "Feels Like",
                  "${weather.feelsLike}°"),

              _info(Icons.compress, "Pressure",
                  "${weather.pressure} mb"),

              _info(Icons.visibility, "Visibility",
                  "${weather.visibility} km"),

              _info(Icons.sunny, "UV",
                  weather.uvIndex),
            ],
          )
        ],
      ),
    );
  }

  Widget _info(
    IconData icon,
    String title,
    String value,
  ) {
    return SizedBox(
      width: 90,
      child: Column(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          )
        ],
      ),
    );
  }
}