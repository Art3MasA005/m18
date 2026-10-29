import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:real_time_location_tracker/services/routing_service.dart';

class LocationTrackerScreen extends StatefulWidget {
  const LocationTrackerScreen({super.key});

  @override
  State<LocationTrackerScreen> createState() => _LocationTrackerScreenState();
}

class _LocationTrackerScreenState extends State<LocationTrackerScreen> {
  // Default Dhaka position (Hanif Flyover / Wari area as shown in assignment)
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

  // Selected Destination & Real Road Routing
  LatLng? _destinationLocation;
  String _destinationName = 'Selected Destination';
  List<LatLng> _roadRoutePoints = [];
  double? _distanceInMeters;
  double? _durationInSeconds;
  List<String> _routeInstructions = [];
  int _currentInstructionIndex = 0;
  bool _isFetchingRoute = false;

  // In-App Turn-By-Turn Navigation
  bool _isNavigating = false;
  double _currentBearing = 0.0;
  Timer? _navigationProgressTimer;
  int _navRoutePointIndex = 0;

  // Search & Places
  final TextEditingController _searchController = TextEditingController();
  List<PlaceSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  // Demo walk coordinates along Dhaka road (for emulator movement testing)
  final List<LatLng> _demoDhakaRoute = const [
    LatLng(23.7216771, 90.4165835),
    LatLng(23.7225000, 90.4178000),
    LatLng(23.7234000, 90.4192000),
    LatLng(23.7245000, 90.4208000),
    LatLng(23.7257000, 90.4225000),
    LatLng(23.7268000, 90.4241000),
    LatLng(23.7280000, 90.4258000),
    LatLng(23.7292000, 90.4273000),
    LatLng(23.7305000, 90.4289000),
  ];

  static const String _markerIdVal = 'current_location_marker';
  static const String _destinationMarkerIdVal = 'destination_marker';
  static const String _polylineIdVal = 'tracking_route_polyline';
  static const String _roadRoutePolylineIdVal = 'road_route_polyline';

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _countdownTimer?.cancel();
    _navigationProgressTimer?.cancel();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Initialize permissions and start 10-second updates
  Future<void> _initLocationTracking() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking location services...';
    });

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Location services disabled. Please enable GPS.';
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

    await _fetchInitialLocation();
    _startPeriodicTracking();
  }

  /// Task 1: Fetch initial location and animate camera
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
        _statusMessage = 'Live GPS active';
      });
      _animateCameraToLocation(_initialPosition);
    }
  }

  /// Task 2: Real-Time Location Updates every 10 seconds
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

  Future<void> _fetchAndUpdateCurrentLocation() async {
    if (_isNavigating) return;

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

  void _advanceSimulatedStep() {
    if (_demoDhakaRoute.isEmpty) return;
    _simulatedIndex = (_simulatedIndex + 1) % _demoDhakaRoute.length;
    final LatLng nextPoint = _demoDhakaRoute[_simulatedIndex];
    _handleNewLocation(nextPoint);
  }

  /// Task 3: Update marker position & append to traveled polyline
  void _handleNewLocation(LatLng newLatLng) {
    if (!mounted) return;

    setState(() {
      _currentLocation = newLatLng;

      if (_polylineCoordinates.isEmpty) {
        _polylineCoordinates.add(newLatLng);
      } else {
        // Calculate distance from previous tracked point
        final double distFromLast = Geolocator.distanceBetween(
          _polylineCoordinates.last.latitude,
          _polylineCoordinates.last.longitude,
          newLatLng.latitude,
          newLatLng.longitude,
        );

        // Only append realistic steps (< 1500m). If GPS jumped/teleported, reset polyline so no straight lines cut across town!
        if (distFromLast > 1500) {
          _polylineCoordinates.clear();
          _polylineCoordinates.add(newLatLng);
        } else if (distFromLast > 1.5) {
          _polylineCoordinates.add(newLatLng);
        }
      }

      if (_destinationLocation != null) {
        _distanceInMeters = Geolocator.distanceBetween(
          newLatLng.latitude,
          newLatLng.longitude,
          _destinationLocation!.latitude,
          _destinationLocation!.longitude,
        );
        _currentBearing = _calculateBearing(newLatLng, _destinationLocation!);
      }
    });

    // Task 1: Animate map camera to user location smoothly
    if (!_isNavigating && _destinationLocation == null) {
      _animateCameraToLocation(newLatLng);
      _showMarkerInfoWindow();
    }
  }

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

  /// Select Destination via Map Tap, Search, or Quick Chips
  Future<void> _selectDestination(LatLng target, {String? placeName}) async {
    final LatLng current = _currentLocation ?? _initialPosition;

    setState(() {
      _destinationLocation = target;
      _destinationName = placeName ?? 'Selected Destination';
      _isFetchingRoute = true;
      _showSearchResults = false;
      _searchController.text = _destinationName;
      _currentBearing = _calculateBearing(current, target);
    });

    _showSnackBar('Selected "$_destinationName". Finding road route...');

    // Fetch REAL driving road route following streets (OSRM)
    final RouteResult result = await RoutingService.fetchRoadRoute(current, target);

    if (!mounted) return;

    setState(() {
      _isFetchingRoute = false;
      _roadRoutePoints = result.points;
      _distanceInMeters = result.distanceInMeters;
      _durationInSeconds = result.durationInSeconds;
      _routeInstructions = result.instructions;
    });

    _showSnackBar('Road route found: ${_formatDistance(_distanceInMeters)} along actual streets!');
    _fitRouteBounds(_roadRoutePoints.isNotEmpty ? _roadRoutePoints : [current, target]);
  }

  /// Search places by text
  Future<void> _onSearchChanged(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final results = await RoutingService.searchPlaces(query);

    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
      _showSearchResults = results.isNotEmpty;
    });
  }

  /// Start In-App Turn-By-Turn Navigation following REAL road route points
  void _startInAppNavigation() {
    if (_destinationLocation == null || _roadRoutePoints.isEmpty) return;
    final LatLng current = _currentLocation ?? _initialPosition;

    setState(() {
      _isNavigating = true;
      _navRoutePointIndex = 0;
      _currentInstructionIndex = 0;
      _currentBearing = _calculateBearing(current, _roadRoutePoints.first);
    });

    _animateNavigationCamera(current, _currentBearing);
    _showSnackBar('In-App Navigation Active: Following street route!');

    // Smooth step-by-step road navigation simulator along the actual street points
    _navigationProgressTimer?.cancel();
    _navigationProgressTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      if (!_isNavigating || _destinationLocation == null) {
        timer.cancel();
        return;
      }

      if (_navRoutePointIndex < _roadRoutePoints.length - 1) {
        _navRoutePointIndex++;
        final LatLng currentPoint = _roadRoutePoints[_navRoutePointIndex];
        final LatLng nextPoint = _navRoutePointIndex + 1 < _roadRoutePoints.length
            ? _roadRoutePoints[_navRoutePointIndex + 1]
            : _destinationLocation!;

        final double bearing = _calculateBearing(currentPoint, nextPoint);
        final double distToDest = Geolocator.distanceBetween(
          currentPoint.latitude,
          currentPoint.longitude,
          _destinationLocation!.latitude,
          _destinationLocation!.longitude,
        );

        setState(() {
          _currentLocation = currentPoint;
          _currentBearing = bearing;
          _distanceInMeters = distToDest;

          if (_polylineCoordinates.isEmpty || _polylineCoordinates.last != currentPoint) {
            _polylineCoordinates.add(currentPoint);
          }

          // Advance instructions periodically along the route
          if (_routeInstructions.isNotEmpty && _navRoutePointIndex % 4 == 0) {
            _currentInstructionIndex = (_currentInstructionIndex + 1) % _routeInstructions.length;
          }
        });

        _animateNavigationCamera(currentPoint, bearing);

        if (distToDest < 25 || _navRoutePointIndex >= _roadRoutePoints.length - 1) {
          timer.cancel();
          _onArrivedAtDestination();
        }
      } else {
        timer.cancel();
        _onArrivedAtDestination();
      }
    });
  }

  void _stopInAppNavigation() {
    _navigationProgressTimer?.cancel();
    setState(() {
      _isNavigating = false;
    });

    if (_currentLocation != null) {
      _animateCameraToLocation(_currentLocation!);
    }
    _showSnackBar('Navigation ended.');
  }

  void _onArrivedAtDestination() {
    _navigationProgressTimer?.cancel();
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
            Text('Arrived! 🎉'),
          ],
        ),
        content: Text(
          'You have reached "$_destinationName" successfully via real road routes!',
          style: const TextStyle(fontSize: 15),
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _clearDestination() {
    _navigationProgressTimer?.cancel();
    setState(() {
      _destinationLocation = null;
      _roadRoutePoints.clear();
      _distanceInMeters = null;
      _durationInSeconds = null;
      _routeInstructions.clear();
      _isNavigating = false;
      _searchController.clear();
      _showSearchResults = false;
    });
    if (_currentLocation != null) {
      _animateCameraToLocation(_currentLocation!);
    }
    _showSnackBar('Destination cleared.');
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (_mapController == null || points.isEmpty) return;

    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;

    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70.0),
    );
  }

  void _animateCameraToLocation(LatLng target) {
    if (_mapController == null) return;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 16.0,
          tilt: 0.0,
          bearing: 0.0,
        ),
      ),
    );
  }

  void _animateNavigationCamera(LatLng target, double bearing) {
    if (_mapController == null) return;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 17.5,
          tilt: 50.0,
          bearing: bearing,
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

  String _formatETA(double? meters, double? seconds) {
    if (meters == null) return '--';
    final int mins = seconds != null && seconds > 0
        ? max(1, (seconds / 60).round())
        : max(1, (meters / 400).round());
    final DateTime eta = DateTime.now().add(Duration(minutes: mins));
    final int hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final String minute = eta.minute.toString().padLeft(2, '0');
    final String ampm = eta.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm (~$mins min)';
  }

  /// Open Choose Destination Modal Bottom Sheet
  void _openDestinationPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.place, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Choose Destination',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Popular Spots in Dhaka (1-Tap Selection)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    ...RoutingService.popularDestinations.map((dest) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          child: Icon(dest.icon, color: Colors.blue.shade700, size: 20),
                        ),
                        title: Text(
                          dest.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          dest.subtitle,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        onTap: () {
                          Navigator.pop(context);
                          _selectDestination(dest.position, placeName: dest.title);
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng activeLocation = _currentLocation ?? _initialPosition;

    // Task 4: Marker with Information Window
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId(_markerIdVal),
        position: activeLocation,
        infoWindow: InfoWindow(
          title: 'My Current Location',
          snippet: '${activeLocation.latitude.toStringAsFixed(6)},${activeLocation.longitude.toStringAsFixed(6)}',
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
            title: _destinationName,
            snippet: _formatDistance(_distanceInMeters),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
    };

    final Set<Polyline> polylines = {
      // Task 3: Polyline Tracking connecting user's traveled path
      if (_polylineCoordinates.length > 1)
        Polyline(
          polylineId: const PolylineId(_polylineIdVal),
          points: _polylineCoordinates,
          color: const Color(0xFF1976D2),
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      // REAL Road Route (following exact street lines and curves)
      if (_roadRoutePoints.isNotEmpty)
        Polyline(
          polylineId: const PolylineId(_roadRoutePolylineIdVal),
          points: _roadRoutePoints,
          color: _isNavigating ? const Color(0xFF00C853) : const Color(0xFF1565C0),
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isNavigating ? 'In-App Navigation' : 'Real-Time Location Tracker',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.lightGreenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isSimulatingRoute
                      ? 'Simulated Walk (10s): step ${_simulatedIndex + 1}/${_demoDhakaRoute.length}'
                      : 'Live GPS: Next update in ${_secondsUntilNextUpdate}s',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: _isNavigating ? const Color(0xFF1B5E20) : const Color(0xFF1976D2),
        elevation: 2,
        actions: [
          if (!_isNavigating) ...[
            IconButton(
              tooltip: 'Choose Destination',
              icon: const Icon(Icons.add_location_alt_outlined, color: Colors.white),
              onPressed: _openDestinationPickerModal,
            ),
            IconButton(
              tooltip: _isSimulatingRoute ? 'Switch to Real GPS' : 'Simulate Emulator Walk (Dhaka)',
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
                      ? 'Walk simulation active: moving along Dhaka road every 10s'
                      : 'Real GPS mode active: polling device sensor every 10s',
                );
              },
            ),
          ],
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
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            onTap: (LatLng point) {
              _selectDestination(
                point,
                placeName: 'Map Location (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})',
              );
            },
            onLongPress: (LatLng point) {
              _selectDestination(
                point,
                placeName: 'Dropped Pin (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})',
              );
            },
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              if (_currentLocation != null) {
                _animateCameraToLocation(_currentLocation!);
                _showMarkerInfoWindow();
              }
            },
          ),

          // Search Bar & Popular Destination Quick Chips Floating on Top
          if (!_isNavigating)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search place (e.g. Gulshan, Dhanmondi, Wari)...',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF1976D2)),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : (_searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.grey),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchResults = [];
                                          _showSearchResults = false;
                                        });
                                      },
                                    )
                                  : null),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    // Quick Destination Horizontal Chips
                    if (!_showSearchResults && _destinationLocation == null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: RoutingService.popularDestinations.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final dest = RoutingService.popularDestinations[index];
                            return ActionChip(
                              avatar: Icon(dest.icon, size: 15, color: const Color(0xFF1976D2)),
                              label: Text(
                                dest.title,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              backgroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              onPressed: () {
                                _selectDestination(dest.position, placeName: dest.title);
                              },
                            );
                          },
                        ),
                      ),

                    // Search Suggestions Dropdown
                    if (_showSearchResults && _searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final place = _searchResults[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on, color: Colors.redAccent),
                              title: Text(
                                place.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              subtitle: Text(
                                place.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              onTap: () {
                                _selectDestination(place.position, placeName: place.title);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
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
                    color: const Color(0xFF1B5E20),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
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
                          size: 28,
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
                            Text(
                              _routeInstructions.isNotEmpty
                                  ? _routeInstructions[_currentInstructionIndex]
                                  : 'Follow road to destination',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
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

          // Route Loading Indicator
          if (_isFetchingRoute)
            Positioned(
              bottom: 120,
              left: 32,
              right: 32,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Calculating real road route...', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

          // Tap Hint Banner when no destination selected
          if (_destinationLocation == null && !_isNavigating && !_showSearchResults)
            Positioned(
              bottom: 24,
              left: 16,
              right: 80,
              child: SafeArea(
                child: InkWell(
                  onTap: _openDestinationPickerModal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.black87.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tap map or touch here to pick destination',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // IN-APP NAVIGATION: Bottom Live ETA Dashboard
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
                            _formatETA(_distanceInMeters, _durationInSeconds),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Remaining: ${_formatDistance(_distanceInMeters)} on street',
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
                        color: Colors.black.withValues(alpha: 0.2),
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
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE8F5E9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.directions_car,
                              color: Color(0xFF2E7D32),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _destinationName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _distanceInMeters != null
                                      ? '${_formatDistance(_distanceInMeters)} via real roads • ${_formatETA(_distanceInMeters, _durationInSeconds)}'
                                      : 'Calculating road route...',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1976D2),
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
                                _fitRouteBounds(_roadRoutePoints.isNotEmpty
                                    ? _roadRoutePoints
                                    : [activeLocation, _destinationLocation!]);
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
                              onPressed: _startInAppNavigation,
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
      floatingActionButton: (!_isNavigating && _destinationLocation == null)
          ? FloatingActionButton(
              mini: true,
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              tooltip: 'Center Current Location',
              onPressed: () {
                if (_currentLocation != null) {
                  _animateCameraToLocation(_currentLocation!);
                  _showMarkerInfoWindow();
                }
              },
              child: const Icon(Icons.my_location, size: 20),
            )
          : null,
    );
  }
}
