class WeatherData {
  final String city;
  final String temp;
  final String description;
  final String humidity;
  final String windSpeed;
  final String feelsLike;
  final String pressure;
  final String visibility;
  final String uvIndex;
  final String precipitation;
  final String weatherCode;

  WeatherData({
    required this.city,
    required this.temp,
    required this.description,
    required this.humidity,
    required this.windSpeed,
    required this.feelsLike,
    required this.pressure,
    required this.visibility,
    required this.uvIndex,
    required this.precipitation,
    required this.weatherCode,
  });

  factory WeatherData.fromWttr(Map<String, dynamic> json) {
    final current = json["current_condition"][0];

    return WeatherData(
      city: json["nearest_area"][0]["areaName"][0]["value"],
      temp: current["temp_C"] ?? "0",
      description: current["weatherDesc"][0]["value"] ?? "",
      humidity: current["humidity"] ?? "0",
      windSpeed: current["windspeedKmph"] ?? "0",
      feelsLike: current["FeelsLikeC"] ?? "0",
      pressure: current["pressure"] ?? "0",
      visibility: current["visibility"] ?? "0",
      uvIndex: current["uvIndex"] ?? "0",
      precipitation: current["precipMM"] ?? "0",
      weatherCode: current["weatherCode"] ?? "113",
    );
  }
}