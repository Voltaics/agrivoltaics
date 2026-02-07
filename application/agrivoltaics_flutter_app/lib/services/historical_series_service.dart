import 'dart:convert';

import 'package:http/http.dart' as http;

class HistoricalPoint {
  final DateTime time;
  final double value;

  HistoricalPoint({required this.time, required this.value});
}

class HistoricalSeries {
  final String zoneId;
  final List<HistoricalPoint> points;

  HistoricalSeries({required this.zoneId, required this.points});
}

class HistoricalGraph {
  final String field;
  final String? unit;
  final List<HistoricalSeries> series;

  HistoricalGraph({
    required this.field,
    required this.unit,
    required this.series,
  });
}

class HistoricalResponse {
  final String interval;
  final List<HistoricalGraph> graphs;

  HistoricalResponse({required this.interval, required this.graphs});
}

class HistoricalSeriesService {
  final String endpointUrl;

  HistoricalSeriesService({required this.endpointUrl});

  Future<HistoricalResponse> fetchSeries({
    required String organizationId,
    required String siteId,
    required List<String> zoneIds,
    required List<String> readings,
    required DateTime start,
    required DateTime end,
    String? interval,
    String? idToken,
  }) async {
    final uri = Uri.parse(endpointUrl);
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (idToken != null && idToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $idToken';
    }

    final body = {
      'organizationId': organizationId,
      'siteId': siteId,
      'zoneIds': zoneIds,
      'readings': readings,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    };

    if (interval != null && interval.isNotEmpty) {
      body['interval'] = interval;
    }

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Request failed');
    }

    final intervalValue = data['interval']?.toString() ?? 'HOUR';
    final graphsRaw = (data['graphs'] as List<dynamic>? ?? []);
    final graphs = graphsRaw.map((graph) {
      final graphMap = graph as Map<String, dynamic>;
      final seriesRaw = (graphMap['series'] as List<dynamic>? ?? []);

      final series = seriesRaw.map((seriesItem) {
        final seriesMap = seriesItem as Map<String, dynamic>;
        final pointsRaw = (seriesMap['points'] as List<dynamic>? ?? []);

        final points = pointsRaw.map((point) {
          final pointMap = point as Map<String, dynamic>;
          final timeValue = pointMap['t'];
          final time = DateTime.tryParse(timeValue.toString())?.toLocal() ?? DateTime.now();
          final value = (pointMap['v'] as num?)?.toDouble() ?? 0.0;
          return HistoricalPoint(time: time, value: value);
        }).toList()
          ..sort((a, b) => a.time.compareTo(b.time));

        return HistoricalSeries(
          zoneId: seriesMap['zoneId']?.toString() ?? '',
          points: points,
        );
      }).toList();

      return HistoricalGraph(
        field: graphMap['field']?.toString() ?? '',
        unit: graphMap['unit']?.toString(),
        series: series,
      );
    }).toList();

    return HistoricalResponse(interval: intervalValue, graphs: graphs);
  }
}
