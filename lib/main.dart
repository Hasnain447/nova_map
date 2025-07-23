// FULL UPDATED FILE

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigation with Route',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const NavigationScreen(),
    );
  }
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _destinationController = TextEditingController();
  LatLng _currentLocation = const LatLng(0, 0);
  LatLng? _destinationLocation;
  bool _isSearching = false;
  bool _isLoading = true;
  bool _isTracking = true;
  bool _hasStarted = false;
  List<LatLng> _routePoints = [];
  double _routeDistance = 0.0;
  double _routeDuration = 0.0;
  StreamSubscription<Position>? _locationStream;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    final status = await Permission.location.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required')),
        );
      }
      return;
    }

    _locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(
          (Position position) {
        if (mounted && _isTracking) {
          setState(() {
            _currentLocation = LatLng(
              position.latitude,
              position.longitude,
            );
            _isLoading = false;
          });
          if (_destinationLocation != null) {
            _fetchRoute();
          } else {
            _mapController.move(_currentLocation, _mapController.zoom);
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location error: ${e.toString()}')),
          );
        }
      },
    );
  }

  Future<void> _fetchRoute() async {
    if (_destinationLocation == null) return;

    try {
      final response = await http.get(
        Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
              '${_currentLocation.longitude},${_currentLocation.latitude};'
              '${_destinationLocation!.longitude},${_destinationLocation!.latitude}'
              '?overview=full&geometries=geojson',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['routes'][0]['geometry']['coordinates'];
        final routePoints = geometry
            .map<LatLng>(
                (coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
            .toList();

        if (mounted) {
          setState(() {
            _routePoints = routePoints;
            _routeDistance = data['routes'][0]['distance']?.toDouble() ?? 0.0;
            _routeDuration = data['routes'][0]['duration']?.toDouble() ?? 0.0;
          });

          if (!_hasStarted) {
            _mapController.fitBounds(
              LatLngBounds.fromPoints(
                  [_currentLocation, _destinationLocation!]),
              options: const FitBoundsOptions(padding: EdgeInsets.all(100)),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Route error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _searchDestination(String query) async {
    if (query.isEmpty) {
      if (mounted)
        setState(() {
          _destinationLocation = null;
          _routePoints = [];
          _routeDistance = 0.0;
          _routeDuration = 0.0;
          _isSearching = false;
          _hasStarted = false;
        });
      return;
    }

    if (mounted) setState(() => _isSearching = true);

    try {
      final locations = await locationFromAddress(query);
      if (mounted)
        setState(() {
          _destinationLocation = locations.isNotEmpty
              ? LatLng(locations.first.latitude, locations.first.longitude)
              : null;
          _isSearching = false;
          _hasStarted = false;
        });

      if (_destinationLocation != null) {
        await _fetchRoute();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _destinationLocation = null;
          _routePoints = [];
          _routeDistance = 0.0;
          _routeDuration = 0.0;
          _isSearching = false;
          _hasStarted = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: ${e.toString()}')),
        );
      }
    }
  }

  void _clearDestination() {
    setState(() {
      _destinationLocation = null;
      _routePoints = [];
      _routeDistance = 0.0;
      _routeDuration = 0.0;
      _destinationController.clear();
      _hasStarted = false;
    });
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}min';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}min';
    } else {
      return '${duration.inSeconds}sec';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navigation with Route')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _currentLocation,
              zoom: 15.0,
              interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            children: [
              TileLayer(
                urlTemplate:
                'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.navigation',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    width: 32,
                    height: 32,
                    point: _currentLocation,
                    child: _isTracking
                        ? _hasStarted
                        ? const Icon(Icons.navigation,
                        color: Colors.blue, size: 32)
                        : const GoogleStyleLocationIcon()
                        : const Icon(
                      Icons.location_disabled,
                      color: Colors.grey,
                    ),
                  ),
                  if (_destinationLocation != null)
                    Marker(
                      width: 24,
                      height: 24,
                      point: _destinationLocation!,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _destinationController,
                      decoration: InputDecoration(
                        hintText: 'Enter destination...',
                        prefixIcon: const Icon(Icons.place, color: Colors.red),
                        suffixIcon: _destinationLocation != null
                            ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearDestination,
                        )
                            : null,
                      ),
                      onSubmitted: _searchDestination,
                    ),
                    if (_isSearching)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'btn1',
                  mini: true,
                  onPressed: () => _mapController.move(
                    _currentLocation,
                    _mapController.zoom,
                  ),
                  child: const Icon(Icons.my_location),
                  tooltip: 'Center on current location',
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'btn2',
                  mini: true,
                  onPressed: () => setState(() => _isTracking = !_isTracking),
                  backgroundColor: _isTracking ? Colors.blue : Colors.grey,
                  child: Icon(
                    _isTracking
                        ? Icons.location_searching
                        : Icons.location_disabled,
                    color: Colors.white,
                  ),
                  tooltip: _isTracking ? 'Pause tracking' : 'Resume tracking',
                ),
              ],
            ),
          ),
          if (_destinationLocation != null && _routePoints.isNotEmpty)
            Positioned(
              bottom: 100,
              left: 20,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Distance: ${(_routeDistance / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Time: ${_formatDuration(_routeDuration)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_destinationLocation != null && !_hasStarted)
            Positioned(
              bottom: 20,
              left: 20,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text("Start"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  setState(() => _hasStarted = true);
                  _mapController.move(_currentLocation, 18);
                  _fetchRoute();
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationStream?.cancel();
    _destinationController.dispose();
    super.dispose();
  }
}

class GoogleStyleLocationIcon extends StatelessWidget {
  const GoogleStyleLocationIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const Positioned(
          bottom: 0,
          child: Icon(Icons.arrow_drop_up, color: Colors.blue, size: 16),
        ),
      ],
    );
  }
}
