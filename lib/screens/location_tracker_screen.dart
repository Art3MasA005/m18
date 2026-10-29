import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationTrackerScreen extends StatefulWidget {
  const LocationTrackerScreen({super.key});

  @override
  State<LocationTrackerScreen> createState() => _LocationTrackerScreenState();
}

class _LocationTrackerScreenState extends State<LocationTrackerScreen> {
  // Default camera position matching Dhaka, Bangladesh from assignment screenshot
  static const LatLng _initialPosition = LatLng(23.7216771, 90.4165835);

  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  final List<LatLng> _polylineCoordinates = [];
  Timer? _locationTimer;
  int _secondsUntilNextUpdate = 10;
  Timer? _countdownTimer;
  bool _isLoading = true;
  String _statusMessage = 'Requesting location permission...';
  bool _isSimulatingRoute = false;
  int _simulatedIndex = 0;

  // Route simulation coordinates matching Dhaka Flyover / Wari from screenshot
  final List<LatLng> _demoDhakaRoute = const [
    LatLng(23.7216771, 90.4165835),
    LatLng(23.7225000, 90.4178000),
    LatLng(23.7234000, 90.4192000),
    LatLng(23.7245000, 90.4208000),
    LatLng(23.7257000, 90.4225000),
    LatLng(23.7268000, 90.4241000),
    LatLng(23.7280000, 90.4258000),
  ];

  static const String _markerIdVal = 'current_location_marker';
  static const String _polylineIdVal = 'tracking_route_polyline';

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _countdownTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Initialize location permission, fetch initial position, and start 10s timer
  Future<void> _initLocationTracking() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking location services...';
    });

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Location services are disabled. Please enable GPS.';
      });
      _showSnackBar('Location services are disabled. Please turn on GPS.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Location permission was denied.';
        });
        _showSnackBar('Location permission denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Location permission permanently denied. Enable in Settings.';
      });
      _showSnackBar('Location permission permanently denied.');
      return;
    }

    // Permission granted - get initial location
    await _fetchInitialLocation();

    // Start 10-second periodic timer as required by assignment Task 2
    _startPeriodicTracking();
  }

  /// Fetch initial location and smoothly animate the Google Map camera
  Future<void> _fetchInitialLocation() async {
    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final LatLng initialLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = initialLatLng;
        _polylineCoordinates.clear();
        _polylineCoordinates.add(initialLatLng);
        _isLoading = false;
        _statusMessage = 'Live tracking active (10s intervals)';
      });

      _animateCameraToLocation(initialLatLng);
    } catch (e) {
      debugPrint('Error getting initial location: $e');
      // Fallback to initial position if GPS lock is delayed on emulator
      setState(() {
        _currentLocation ??= _initialPosition;
        if (_polylineCoordinates.isEmpty) {
          _polylineCoordinates.add(_initialPosition);
        }
        _isLoading = false;
        _statusMessage = 'Using location: ${_initialPosition.latitude}, ${_initialPosition.longitude}';
      });
      _animateCameraToLocation(_initialPosition);
    }
  }

  /// Start 10-second interval timer for location updates
  void _startPeriodicTracking() {
    _locationTimer?.cancel();
    _countdownTimer?.cancel();

    _secondsUntilNextUpdate = 10;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsUntilNextUpdate > 1) {
            _secondsUntilNextUpdate--;
          } else {
            _secondsUntilNextUpdate = 10;
          }
        });
      }
    });

    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _fetchAndUpdateCurrentLocation();
    });
  }

  /// Task 2 & 3: Fetch current location every 10 seconds, update marker,
  /// draw polyline connecting previous and current points, and animate camera
  Future<void> _fetchAndUpdateCurrentLocation() async {
    if (_isSimulatingRoute) {
      _advanceSimulatedStep();
      return;
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final LatLng newLatLng = LatLng(position.latitude, position.longitude);
      _handleNewLocation(newLatLng);
    } catch (e) {
      debugPrint('Periodic location update error: $e');
    }
  }

  /// Updates state with new location point, appends to polyline, and animates camera
  void _handleNewLocation(LatLng newLatLng) {
    if (!mounted) return;

    setState(() {
      _currentLocation = newLatLng;

      // Avoid duplicate consecutive points
      if (_polylineCoordinates.isEmpty ||
          _polylineCoordinates.last.latitude != newLatLng.latitude ||
          _polylineCoordinates.last.longitude != newLatLng.longitude) {
        _polylineCoordinates.add(newLatLng);
      }
    });

    // Smooth camera animation to latest position
    _animateCameraToLocation(newLatLng);

    // Keep InfoWindow displayed
    _showMarkerInfoWindow();
  }

  /// Advance route simulation (useful for testing on emulators where GPS is stationary)
  void _advanceSimulatedStep() {
    _simulatedIndex = (_simulatedIndex + 1) % _demoDhakaRoute.length;
    final LatLng nextPoint = _demoDhakaRoute[_simulatedIndex];
    _handleNewLocation(nextPoint);
  }

  /// Smoothly animates the map camera to the target location (Task 1)
  void _animateCameraToLocation(LatLng target) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 16.5,
          tilt: 0,
          bearing: 0,
        ),
      ),
    );
  }

  void _showMarkerInfoWindow() {
    _mapController?.showMarkerInfoWindow(const MarkerId(_markerIdVal));
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng activeLocation = _currentLocation ?? _initialPosition;

    // Marker with InfoWindow (Task 4)
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId(_markerIdVal),
        position: activeLocation,
        infoWindow: InfoWindow(
          title: 'My Current Location',
          snippet: '${activeLocation.latitude},${activeLocation.longitude}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    // Polyline connecting previous and current locations (Task 3)
    final Set<Polyline> polylines = {
      if (_polylineCoordinates.length > 1)
        Polyline(
          polylineId: const PolylineId(_polylineIdVal),
          points: _polylineCoordinates,
          color: const Color(0xFF1E88E5), // Rich vibrant blue
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Real-Time Location Tracker',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 2,
        actions: [
          // Simulation toggle button for convenient emulator testing
          IconButton(
            tooltip: _isSimulatingRoute ? 'Switch to Real GPS' : 'Simulate Emulator Walk',
            icon: Icon(
              _isSimulatingRoute ? Icons.directions_walk : Icons.gps_fixed,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _isSimulatingRoute = !_isSimulatingRoute;
                if (_isSimulatingRoute) {
                  _simulatedIndex = 0;
                  _polylineCoordinates.clear();
                  _polylineCoordinates.add(_demoDhakaRoute[0]);
                  _currentLocation = _demoDhakaRoute[0];
                  _animateCameraToLocation(_demoDhakaRoute[0]);
                }
              });
              _showSnackBar(
                _isSimulatingRoute
                  ? 'Simulation mode active: Updates every 10s along route'
                  : 'Real GPS mode active: Polling Geolocator every 10s',
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map View
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 16.0,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              if (_currentLocation != null) {
                _animateCameraToLocation(_currentLocation!);
                _showMarkerInfoWindow();
              }
            },
          ),

          // Top Info Status Badge
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isSimulatingRoute
                            ? Colors.orange.withValues(alpha: 0.2)
                            : Colors.blue.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isSimulatingRoute ? Icons.directions_walk : Icons.location_on,
                        color: _isSimulatingRoute ? Colors.orange.shade800 : Colors.blue.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isSimulatingRoute
                                ? 'Simulation Mode (Dhaka Flyover Route)'
                                : 'Real-Time GPS Tracker',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Lat: ${activeLocation.latitude.toStringAsFixed(6)}, Lng: ${activeLocation.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        '${_secondsUntilNextUpdate}s',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading overlay during initial fetch
          if (_isLoading)
            Container(
              color: Colors.black38,
              child: Center(
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: FloatingActionButton(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          tooltip: 'Center on My Location',
          onPressed: () {
            if (_currentLocation != null) {
              _animateCameraToLocation(_currentLocation!);
              _showMarkerInfoWindow();
            } else {
              _fetchAndUpdateCurrentLocation();
            }
          },
          child: const Icon(Icons.my_location),
        ),
      ),
    );
  }
}
