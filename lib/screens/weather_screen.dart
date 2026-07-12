import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:orbitx/services/weather_service.dart';
import '../dto/weather_dto.dart';
import '../widgets/current_weather_card.dart';
import '../widgets/hourly_forecast_card.dart';
import '../widgets/forecast_tile.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  Map<String, dynamic>? json;

  @override
  Widget build(BuildContext context) {
    if (json == null) {
      return CircularProgressIndicator(
        backgroundColor: Colors.transparent,
        color: Colors.blue,
      );
    }
    final weather = WeatherData.fromWttr(json!);

    final hourly = json!["weather"][0]["hourly"] as List;

    final daily = json!["weather"] as List;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff0F2027), Color(0xff203A43), Color(0xff2C5364)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              CurrentWeatherCard(weather: weather),

              const SizedBox(height: 24),

              SizedBox(
                height: 130,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: hourly.length,
                  itemBuilder: (_, index) {
                    final h = hourly[index];

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: HourlyForecastCard(
                        hourly: h,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: daily.length,
                itemBuilder: (_, index) {
                  final day = daily[index];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ForecastTile(
                      day: day,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    Geolocator.getLastKnownPosition(forceAndroidLocationManager: true).then(
      (location) => {
        if (location == null)
          {
            Geolocator.getCurrentPosition().then((pos) {
              WeatherService.getWeatherPoint(
                GeoPoint(latitude: pos.latitude, longitude: pos.longitude),
              ).then(
                (val) => {
                  // sharedPreferences.setString(
                  //   "last_location",
                  //   "${pos.latitude},${pos.longitude}",
                  // ),
                  setState(() {
                    json = val;
                  }),
                },
              );
            }),
          }
        else
          {
            WeatherService.getWeatherPoint(
              GeoPoint(
                latitude: location.latitude,
                longitude: location.longitude,
              ),
            ).then(
              (val) => {
                setState(() {
                  json = val;
                }),
              },
            ),
          },
      },
    );
  }
}
