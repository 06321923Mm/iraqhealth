import 'package:flutter/material.dart';

class LocationPickResult {
  const LocationPickResult({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.title,
  });

  final double initialLatitude;
  final double initialLongitude;
  final String? title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late double _lat;
  late double _lng;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLatitude;
    _lng = widget.initialLongitude;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'اختر الموقع'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {
                Navigator.of(context).pop(
                  LocationPickResult(latitude: _lat, longitude: _lng),
                );
              },
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('خط العرض: ${_lat.toStringAsFixed(5)}'),
              Text('خط الطول: ${_lng.toStringAsFixed(5)}'),
              const SizedBox(height: 16),
              const Text('حرّك الدبوس لتحديد الموقع الصحيح'),
            ],
          ),
        ),
      ),
    );
  }
}
