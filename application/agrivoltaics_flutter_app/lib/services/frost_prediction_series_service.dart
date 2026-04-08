import 'dart:convert';

import 'package:http/http.dart' as http;

class FrostTimelinePoint {
  const FrostTimelinePoint({
    required this.time,
    required this.temperature,
    required this.humidity,
    required this.soilTemperature,
    required this.predictedChance,
  });

  final DateTime time;
  final double? temperature;
  final double? humidity;
  final double? soilTemperature;
  final double predictedChance;

  factory FrostTimelinePoint.fromJson(Map<String, dynamic> json) {
    double? _toNullableDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return FrostTimelinePoint(
      time: DateTime.parse(json['timestamp'] as String).toLocal(),
      temperature: _toNullableDouble(json['temperature']),
      humidity: _toNullableDouble(json['humidity']),
      soilTemperature: _toNullableDouble(json['soilTemperature']),
      predictedChance: _toNullableDouble(json['predictedChance']) ?? 0.0,
    );
  }
}

class FrostTimelineResponse {
  const FrostTimelineResponse({
    required this.zoneId,
    required this.interval,
    required this.points,
  });

  final String zoneId;
  final String interval;
  final List<FrostTimelinePoint> points;

  factory FrostTimelineResponse.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List<dynamic>? ?? const []);
    return FrostTimelineResponse(
      zoneId: (json['zoneId'] ?? '').toString(),
      interval: (json['interval'] ?? '15m').toString(),
      points: rawPoints
          .whereType<Map<String, dynamic>>()
          .map(FrostTimelinePoint.fromJson)
          .toList(),
    );
  }
}

class FrostPredictionSeriesService {
  const FrostPredictionSeriesService({
    required this.endpointUrl,
  });

  final String endpointUrl;

  Future<FrostTimelineResponse> fetchTimeline({
    required String organizationId,
    required String siteId,
    required String zoneId,
    required DateTime start,
    required DateTime end,
    required String timezone,
    String? idToken,
  }) async {
    final uri = Uri.parse(endpointUrl);

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (idToken != null && idToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $idToken';
    }

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'organizationId': organizationId,
        'siteId': siteId,
        'zoneId': zoneId,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'timezone': timezone,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Frost timeline request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid frost timeline response format.');
    }

    return FrostTimelineResponse.fromJson(decoded);
  }
}