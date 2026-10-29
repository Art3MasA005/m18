import 'dart:async';
import 'dart:math';
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

  // Selected Destination & In-App Navigation state
  LatLng? _destinationLocation;
  double? _distanceInMeters;
  bool _isNavigating = false;
  double _currentBearing = 0.0;
  Timer? _navigationSimTimer;

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
  static const String _destinationMarkerIdVal = 'destination_marker';
  static const String _polylineIdVal = 'tracking_route_polyline';
  static const String _directionsPolylineIdVal = 'directions_route_polyline';

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _countdownTimer?.cancel();
    _navigationSimTimer?.cancel();
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
    if (_isNavigating) {
      // During active in-app navigation, updates are handled by the navigation loop
      return;
    }

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

      // Update distance if destination is active
      if (_destinationLocation != null) {
        _distanceInMeters = Geolocator.distanceBetween(
          newLatLng.latitude,
          newLatLng.longitude,
          _destinationLocation!.latitude,
          _destinationLocation!.longitude,
        );
        _currentBearing = _calculateBearing(newLatLng, _destinationLocation!);

        // Arrival detection
        if (_isNavigating && _distanceInMeters != null && _distanceInMeters! < 18) {
          _onArrivedAtDestination();
          return;
        }
      }
    });

    // In Navigation Mode, follow user in 3D perspective
    if (_isNavigating) {
      _animateNavigationCamera(newLatLng, _currentBearing);
    } else if (_destinationLocation == null) {
      _animateCameraToLocation(newLatLng);
      _showMarkerInfoWindow();
    }
  }

  /// Calculate compass bearing between two points
  double _calculateBearing(LatLng start, LatLng end) {
    final double startLat = start.latitude * (pi / 180.0);
    final double startLng = start.longitude * (pi / 180.0);
    final double endLat = end.latitude * (pi / 180.0);
    final double endLng = end.longitude * (pi / 180.0);

    final double dLng = endLng - startLng;
    final double y = sin(dLng) * cos(endLat);
    final double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);
    final double brng = atan2(y, x);
    return (brng * (180.0 / pi) + 360.0) % 360.0;
  }

  /// Select a destination by tapping on the map
  void _onMapTapped(LatLng target) {
    if (_isNavigating) return; // Do not overwrite while actively navigating

    final LatLng current = _currentLocation ?? _initialPosition;
    final double distance = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      target.latitude,
      target.longitude,
    );

    setState(() {
      _destinationLocation = target;
      _distanceInMeters = distance;
      _currentBearing = _calculateBearing(current, target);
    });

    _showSnackBar('Destination selected! Tap "Start Navigation" for in-app navigation.');
    _fitRouteBounds(current, target);
  }

  /// Start In-App Turn-By-Turn Navigation Mode
  void _startInAppNavigation() {
    if (_destinationLocation == null) return;
    final LatLng current = _currentLocation ?? _initialPosition;

    setState(() {
      _isNavigating = true;
      _currentBearing = _calculateBearing(current, _destinationLocation!);
    });

    _animateNavigationCamera(current, _currentBearing);
    _showSnackBar('In-App Navigation Started! Guiding to destination...');

    // Live In-App Navigation Simulator for smooth emulator testing
    _navigationSimTimer?.cancel();
    _navigationSimTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isNavigating || _destinationLocation == null || _currentLocation == null) {
        timer.cancel();
        return;
      }

      // Step towards destination smoothly (approx 12 meters per step)
      final double latDiff = _destinationLocation!.latitude - _currentLocation!.latitude;
      final double lngDiff = _destinationLocation!.longitude - _currentLocation!.longitude;
      final double totalDist = sqrt(latDiff * latDiff + lngDiff * lngDiff);

      if (totalDist < 0.00015 || (_distanceInMeters != null && _distanceInMeters! < 18)) {
        timer.cancel();
        _onArrivedAtDestination();
        return;
      }

      // Fractional progress towards destination
      const double stepRatio = 0.08;
      final LatLng nextPoint = LatLng(
        _currentLocation!.latitude + (latDiff * stepRatio),
        _currentLocation!.longitude + (lngDiff * stepRatio),
      );

      _handleNewLocation(nextPoint);
    });
  }

  /// Stop In-App Navigation Mode
  void _stopInAppNavigation() {
    _navigationSimTimer?.cancel();
    setState(() {
      _isNavigating = false;
    });

    if (_currentLocation != null) {
      _animateCameraToLocation(_currentLocation!);
    }
    _showSnackBar('Navigation ended.');
  }

  /// Arrived at Destination handler
  void _onArrivedAtDestination() {
    _navigationSimTimer?.cancel();
    setState(() {
      _isNavigating = false;
      _distanceInMeters = 0;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 28),
            SizedBox(width: 10),
            Text('You Have Arrived!'),
          ],
        ),
        content: const Text(
          'You have reached your destination successfully! 🎉',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _clearDestination();
            },
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }

  /// Clear the selected destination
  void _clearDestination() {
    _navigationSimTimer?.cancel();
    setState(() {
      _destinationLocation = null;
      _distanceInMeters = null;
      _isNavigating = false;
    });
    if (_currentLocation != null) {
      _animateCameraToLocation(_currentLocation!);
    }
    _showSnackBar('Destination cleared.');
  }

  /// Fit both current location and destination in map view
  void _fitRouteBounds(LatLng p1, LatLng p2) {
    if (_mapController == null) return;

    final double south = p1.latitude < p2.latitude ? p1.latitude : p2.latitude;
    final double north = p1.latitude > p2.latitude ? p1.latitude : p2.latitude;
    final double west = p1.longitude < p2.longitude ? p1.longitude : p2.longitude;
    final double east = p1.longitude > p2.longitude ? p1.longitude : p2.longitude;

    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 90.0),
    );
  }

  /// 3D Navigation Camera following user with heading bearing and tilt
  void _animateNavigationCamera(LatLng target, double bearing) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 18.5,
          tilt: 55.0, // 3D driver perspective
          bearing: bearing,
        ),
      ),
    );
  }

  /// Advance route simulation for Dhaka route
  void _advanceSimulatedStep() {
    _simulatedIndex = (_simulatedIndex + 1) % _demoDhakaRoute.length;
    final LatLng nextPoint = _demoDhakaRoute[_simulatedIndex];
    _handleNewLocation(nextPoint);
  }

  /// Standard map camera animation
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '0 m';
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatETA(double? meters) {
    if (meters == null) return '--';
    final int mins = max(1, (meters / 400).round());
    final DateTime eta = DateTime.now().add(Duration(minutes: mins));
    final int hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final String minute = eta.minute.toString().padLeft(2, '0');
    final String ampm = eta.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm (~$mins min)';
  }

  @override
  Widget build(BuildContext context) {
    final LatLng activeLocation = _currentLocation ?? _initialPosition;

    // Markers: Current location marker + Destination marker
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId(_markerIdVal),
        position: activeLocation,
        infoWindow: InfoWindow(
          title: 'My Current Location',
          snippet: '${activeLocation.latitude},${activeLocation.longitude}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _isNavigating ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed,
        ),
      ),
      if (_destinationLocation != null)
        Marker(
          markerId: const MarkerId(_destinationMarkerIdVal),
          position: _destinationLocation!,
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: _formatDistance(_distanceInMeters),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
    };

    // Polylines: Tracking history + In-App Navigation Route
    final Set<Polyline> polylines = {
      if (_polylineCoordinates.length > 1)
        Polyline(
          polylineId: const PolylineId(_polylineIdVal),
          points: _polylineCoordinates,
          color: const Color(0xFF1E88E5), // Blue tracking line
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      if (_destinationLocation != null)
        Polyline(
          polylineId: const PolylineId(_directionsPolylineIdVal),
          points: [activeLocation, _destinationLocation!],
          color: _isNavigating ? const Color(0xFF00E676) : const Color(0xFF7C4DFF), // Vibrant Green during Nav
          width: _isNavigating ? 8 : 6,
          patterns: _isNavigating
              ? [] // Solid glowing green route during navigation
              : [PatternItem.dash(24), PatternItem.gap(12)],
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNavigating ? 'Navigating to Destination' : 'Real-Time Location Tracker',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 19,
          ),
        ),
        backgroundColor: _isNavigating ? const Color(0xFF1B5E20) : Colors.blue,
        elevation: 2,
        actions: [
          if (!_isNavigating)
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
            zoomControlsEnabled: !_isNavigating,
            compassEnabled: true,
            mapToolbarEnabled: false,
            onTap: _onMapTapped,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              if (_currentLocation != null) {
                _animateCameraToLocation(_currentLocation!);
                _showMarkerInfoWindow();
              }
            },
          ),

          // IN-APP NAVIGATION: Top Turn-by-Turn Guidance HUD
          if (_isNavigating)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20), // Rich navigation green
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatDistance(_distanceInMeters),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            const Text(
                              'Proceed along route to destination',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 24),
                        tooltip: 'Exit Navigation',
                        onPressed: _stopInAppNavigation,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // REGULAR MODE: Top Info Status Badge
          if (!_isNavigating)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
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

          // Tap Hint Banner when no destination is selected
          if (_destinationLocation == null && !_isNavigating)
            Positioned(
              top: 76,
              left: 32,
              right: 32,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app, color: Colors.amberAccent, size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Tap anywhere on map to set Destination & Navigate',
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // IN-APP NAVIGATION: Bottom Navigation Dashboard
          if (_isNavigating)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatETA(_distanceInMeters),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Remaining: ${_formatDistance(_distanceInMeters)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Exit Nav'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _stopInAppNavigation,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // REGULAR MODE: Bottom Destination & Start In-App Navigation Card
          if (_destinationLocation != null && !_isNavigating)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE8F5E9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.place,
                              color: Color(0xFF2E7D32),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected Destination',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _distanceInMeters != null
                                      ? '${_formatDistance(_distanceInMeters)} away • ${_formatETA(_distanceInMeters)}'
                                      : 'Calculating...',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E88E5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            tooltip: 'Clear Destination',
                            onPressed: _clearDestination,
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.center_focus_strong, size: 18),
                              label: const Text('Focus Route'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue.shade800,
                                side: BorderSide(color: Colors.blue.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                _fitRouteBounds(activeLocation, _destinationLocation!);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.navigation, size: 18),
                              label: const Text('Start Navigation'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _startInAppNavigation, // In-App navigation!
                            ),
                          ),
                        ],
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
        padding: EdgeInsets.only(
          bottom: _isNavigating
              ? 95.0
              : (_destinationLocation != null ? 140.0 : 16.0),
        ),
        child: FloatingActionButton(
          backgroundColor: _isNavigating ? const Color(0xFF1B5E20) : Colors.blue,
          foregroundColor: Colors.white,
          tooltip: 'Center on My Location',
          onPressed: () {
            if (_currentLocation != null) {
              if (_isNavigating) {
                _animateNavigationCamera(_currentLocation!, _currentBearing);
              } else {
                _animateCameraToLocation(_currentLocation!);
                _showMarkerInfoWindow();
              }
            } else {
              _fetchAndUpdateCurrentLocation();
            }
          },
          child: Icon(_isNavigating ? Icons.navigation : Icons.my_location),
        ),
      ),
    );
  }
}
