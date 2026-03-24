import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/cache/location_cache.dart';
import '../../core/config.dart';
import '../../core/maps/geocoder_proxy_client.dart';
import '../../core/maps/yandex_map_types.dart';
import '../../core/maps/yandex_map_view.dart';
import '../../core/state/providers.dart';

class LocationPickerScreen extends StatelessWidget {
  const LocationPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DeliveryAddressPage();
  }
}

class DeliveryAddressPage extends ConsumerStatefulWidget {
  const DeliveryAddressPage({super.key});

  @override
  ConsumerState<DeliveryAddressPage> createState() =>
      _DeliveryAddressPageState();
}

class _DeliveryAddressPageState extends ConsumerState<DeliveryAddressPage> {
  static const _defaultLat = restaurantLat;
  static const _defaultLon = restaurantLng;
  static const _defaultZoom = 12.5;
  static const _selectedZoom = 16.0;
  static const _searchDebounce = Duration(milliseconds: 300);
  static const _targetAccuracyMeters = 50.0;
  static const _simulatorWarning =
      'Simulator location is not set. Simulator -> Features -> Location -> Custom Location (41.2995, 69.2401)';

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _proxyGeocoder = GeocoderProxyClient();
  final _suggestions = <ProxyPlace>[];

  Timer? _debounce;
  // Incremented on each query change so older autocomplete responses can be ignored.
  int _searchToken = 0;

  double _mapLat = _defaultLat;
  double _mapLon = _defaultLon;
  double _mapZoom = _defaultZoom;
  double? _userLat;
  double? _userLon;

  bool _searching = false;
  bool _resolving = false;
  bool _locating = false;
  bool _permissionDeniedForever = false;
  bool _needsPinRefinement = false;

  String _placeName = '';
  String _formattedAddress = '';

  @override
  void initState() {
    super.initState();
    final saved = ref.read(deliveryLocationProvider);
    if (saved == null) return;
    _mapLat = saved.lat;
    _mapLon = saved.lng;
    _mapZoom = _selectedZoom;
    final savedAddress = saved.address.trim();
    if (_looksLikeCoordinates(savedAddress) ||
        _isGenericPlaceLabel(savedAddress)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_reverseAndSelect(saved.lat, saved.lng));
      });
    } else {
      _placeName = savedAddress.split(',').first.trim();
      _formattedAddress = savedAddress;
      _searchController.text = _bestPlaceLabel(_placeName, _formattedAddress);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _proxyGeocoder.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _validLatLon(double lat, double lon) {
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  bool _looksLikeCoordinates(String value) {
    return RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$')
        .hasMatch(value.trim());
  }

  bool _isGenericPlaceLabel(String value) {
    final text = value.trim().toLowerCase();
    return text == 'uzbekistan' ||
        text == 'o\'zbekiston' ||
        text == 'узбекистан' ||
        text == 'ўзбекистон' ||
        text == 'tashkent' ||
        text == 'toshkent' ||
        text == 'ташкент' ||
        text.contains('махалл') ||
        text.contains('махалля') ||
        text.contains('махаллин') ||
        text.contains('mahall') ||
        text.contains('сход граждан') ||
        text.contains('мфй');
  }

  String _extractSpecificAddressPart(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return value.trim();
    for (final part in parts.reversed) {
      if (_isGenericPlaceLabel(part)) continue;
      return part;
    }
    return parts.last;
  }

  String _bestPlaceLabel(String placeName, String formattedAddress) {
    final short = placeName.trim();
    final long = formattedAddress.trim();
    if (short.isEmpty) return long;
    if (long.isEmpty) return short;
    if (_isGenericPlaceLabel(short)) {
      return _extractSpecificAddressPart(long);
    }
    return short;
  }

  bool _hasHouseNumber(String value) {
    return RegExp(
      r'\b\d+[A-Za-zА-Яа-я]?\b',
      caseSensitive: false,
    ).hasMatch(value);
  }

  bool _isAdministrativeKind(String kind) {
    switch (kind.trim().toLowerCase()) {
      case 'country':
      case 'province':
      case 'area':
      case 'locality':
      case 'district':
        return true;
      default:
        return false;
    }
  }

  bool _isPreciseSearchResult(ProxyPlace place) {
    final kind = place.kind.trim().toLowerCase();
    final precision = place.precision.trim().toLowerCase();
    final combined = '${place.placeName}, ${place.formattedAddress}';
    if (kind == 'house') return true;
    if (precision == 'exact' || precision == 'number') return true;
    if (_hasHouseNumber(combined)) return true;
    if (kind == 'street' &&
        !_isGenericPlaceLabel(place.placeName) &&
        !_isGenericPlaceLabel(place.formattedAddress)) {
      return true;
    }
    return false;
  }

  int _searchResultScore(ProxyPlace place) {
    final kind = place.kind.trim().toLowerCase();
    final precision = place.precision.trim().toLowerCase();
    final combined = '${place.placeName}, ${place.formattedAddress}';
    var score = 0;
    if (_isPreciseSearchResult(place)) score += 1000;
    if (kind == 'house') score += 500;
    if (kind == 'street') score += 250;
    if (_hasHouseNumber(combined)) score += 180;
    if (precision == 'exact' || precision == 'number') score += 160;
    if (precision == 'near' || precision == 'street') score += 80;
    if (_isAdministrativeKind(kind)) score -= 500;
    if (_isGenericPlaceLabel(place.placeName) ||
        _isGenericPlaceLabel(place.formattedAddress)) {
      score -= 220;
    }
    return score;
  }

  List<ProxyPlace> _rankSearchResults(List<ProxyPlace> places) {
    final ranked = places.toList();
    ranked
        .sort((a, b) => _searchResultScore(b).compareTo(_searchResultScore(a)));
    return ranked;
  }

  ProxyPlace? _bestAutoSelection(List<ProxyPlace> places) {
    for (final place in places) {
      if (_isPreciseSearchResult(place)) return place;
    }
    return null;
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searching = false;
        _suggestions.clear();
      });
      return;
    }

    final token = ++_searchToken;
    _debounce = Timer(_searchDebounce, () {
      unawaited(_performSearch(query, token));
    });
  }

  String _proxyLang() {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    switch (code) {
      case 'uz':
        return 'uz_UZ';
      case 'en':
        return 'en_US';
      default:
        return 'ru_RU';
    }
  }

  Future<void> _performSearch(
    String query,
    int token, {
    bool autoSelectTop = false,
    bool showNoResults = false,
  }) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final results = await _proxyGeocoder.geocode(
        text: query,
        lang: _proxyLang(),
        results: 5,
      );
      if (!mounted || token != _searchToken) return;
      final limited = _rankSearchResults(results).take(5).toList();
      setState(() {
        _suggestions
          ..clear()
          ..addAll(limited);
      });
      if (limited.isNotEmpty && autoSelectTop) {
        final selected = _bestAutoSelection(limited);
        if (selected != null) {
          _applyPlace(selected);
        } else {
          _applyPlace(limited.first, requirePinRefinement: true);
          _showSnack('Укажите улицу и дом или поставьте точку дома на карте');
        }
      } else if (limited.isEmpty && showNoResults) {
        _showSnack('Адрес не найден');
      }
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() => _suggestions.clear());
      if (showNoResults) {
        _showSnack('Адрес не найден');
      }
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => _searching = false);
      }
    }
  }

  void _runManualSearch() {
    final query = _searchController.text.trim();
    final token = ++_searchToken;
    _debounce?.cancel();
    unawaited(
      _performSearch(
        query,
        token,
        autoSelectTop: true,
        showNoResults: true,
      ),
    );
  }

  void _applyPlace(
    ProxyPlace place, {
    bool markAsUser = false,
    bool requirePinRefinement = false,
  }) {
    setState(() {
      _mapLat = place.lat;
      _mapLon = place.lon;
      _mapZoom = _selectedZoom;
      _placeName = _bestPlaceLabel(
          place.placeName.trim(), place.formattedAddress.trim());
      _formattedAddress = place.formattedAddress.trim();
      _needsPinRefinement = requirePinRefinement;
      _suggestions.clear();
      if (markAsUser) {
        _userLat = place.lat;
        _userLon = place.lon;
        _needsPinRefinement = false;
      }
    });
    _searchController.text =
        _placeName.isEmpty ? _formattedAddress : _placeName;
    _searchFocusNode.unfocus();
  }

  Future<void> _reverseAndSelect(
    double lat,
    double lon, {
    bool markAsUser = false,
  }) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      final place = await _proxyGeocoder.reverse(
        lat: lat,
        lon: lon,
        lang: _proxyLang(),
      );
      if (!mounted || place == null) return;
      _applyPlace(place, markAsUser: markAsUser);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _selectSuggestion(ProxyPlace place) async {
    _searchToken++;
    _debounce?.cancel();
    final needsRefinement = !_isPreciseSearchResult(place);
    _applyPlace(place, requirePinRefinement: needsRefinement);
    if (needsRefinement) {
      _showSnack('Укажите улицу и дом или поставьте точку дома на карте');
    }
  }

  Future<void> _onMapTap(double lat, double lon) async {
    _searchFocusNode.unfocus();
    setState(() {
      _mapLat = lat;
      _mapLon = lon;
      _mapZoom = _selectedZoom;
      _needsPinRefinement = false;
      _suggestions.clear();
    });
    await _reverseAndSelect(lat, lon);
  }

  Future<Position?> _safeCurrentPosition() async {
    Position? best;
    final attempts = <(LocationAccuracy, Duration)>[
      (LocationAccuracy.bestForNavigation, const Duration(seconds: 10)),
      (LocationAccuracy.high, const Duration(seconds: 8)),
      (LocationAccuracy.medium, const Duration(seconds: 6)),
    ];
    for (final attempt in attempts) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: attempt.$1,
          timeLimit: attempt.$2,
        );
        if (!_validLatLon(position.latitude, position.longitude)) continue;
        if (position.accuracy <= _targetAccuracyMeters) return position;
        if (best == null || position.accuracy < best.accuracy) {
          best = position;
        }
      } catch (_) {
        // Try the next strategy.
      }
    }
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          _validLatLon(lastKnown.latitude, lastKnown.longitude)) {
        if (best == null || lastKnown.accuracy < best.accuracy) {
          best = lastKnown;
        }
      }
    } catch (_) {
      // Ignore last known lookup issues.
    }
    return best;
  }

  Future<Position?> _refineCurrentPosition(Position current) async {
    var best = current;
    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 12),
      );
      if (_validLatLon(fresh.latitude, fresh.longitude) &&
          fresh.accuracy < best.accuracy) {
        best = fresh;
      }
      if (best.accuracy <= _targetAccuracyMeters) return best;
    } catch (_) {
      // Fall through to the stream-based retry.
    }
    try {
      final live = await Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).first.timeout(const Duration(seconds: 8));
      if (_validLatLon(live.latitude, live.longitude) &&
          live.accuracy < best.accuracy) {
        best = live;
      }
    } catch (_) {
      // Return the best fix seen so far.
    }
    return best;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _fallbackToTashkent() {
    setState(() {
      _mapLat = _defaultLat;
      _mapLon = _defaultLon;
      _mapZoom = _defaultZoom;
      _userLat = null;
      _userLon = null;
      _needsPinRefinement = false;
      _placeName = '';
      _formattedAddress = '';
      _suggestions.clear();
    });
    _searchController.clear();
    // iOS Simulator often reports a default US location until a custom one is set.
    _showSnack(_simulatorWarning);
  }

  void _zoomInMap() {
    setState(() {
      _mapZoom = (_mapZoom + 1).clamp(10.0, 19.0).toDouble();
    });
  }

  void _zoomOutMap() {
    setState(() {
      _mapZoom = (_mapZoom - 1).clamp(10.0, 19.0).toDouble();
    });
  }

  Future<void> _useCurrentLocation() async {
    _searchFocusNode.unfocus();
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _fallbackToTashkent();
        return;
      }

      var permission = await Permission.locationWhenInUse.status;
      if (permission.isDenied) {
        permission = await Permission.locationWhenInUse.request();
      }
      if (permission.isPermanentlyDenied || permission.isRestricted) {
        if (mounted) setState(() => _permissionDeniedForever = true);
        _showSnack('Location permission denied.');
        return;
      }
      if (!permission.isGranted) {
        _showSnack('Location permission denied.');
        return;
      }

      var position = await _safeCurrentPosition();
      if (position == null) {
        _fallbackToTashkent();
        return;
      }
      if (position.accuracy > _targetAccuracyMeters) {
        _showSnack('Уточняю местоположение…');
        position = await _refineCurrentPosition(position);
        if (position == null) {
          _fallbackToTashkent();
          return;
        }
      }

      final distanceFromTashkent = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _defaultLat,
        _defaultLon,
      );
      if (distanceFromTashkent > 500000) {
        _fallbackToTashkent();
        return;
      }

      final place = await _proxyGeocoder.reverse(
        lat: position.latitude,
        lon: position.longitude,
        lang: _proxyLang(),
      );
      if (place == null) {
        _fallbackToTashkent();
        return;
      }

      _applyPlace(place, markAsUser: true);
      _showSnack(
          place.placeName.isEmpty ? place.formattedAddress : place.placeName);
    } catch (_) {
      _fallbackToTashkent();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_formattedAddress.trim().isEmpty) {
      await _reverseAndSelect(_mapLat, _mapLon);
    }
    final address = _formattedAddress.trim();
    if (address.isEmpty) {
      _showSnack('Выберите адрес доставки');
      return;
    }
    if (_needsPinRefinement) {
      _showSnack('Укажите дом точкой на карте или добавьте улицу и номер дома');
      return;
    }

    final session = ref.read(userSessionProvider);
    final scope = session == null
        ? null
        : session.userId > 0
            ? 'uid_${session.userId}'
            : session.phone.trim().isNotEmpty
                ? 'phone_${session.phone.trim()}'
                : null;

    if (scope != null) {
      await LocationCache().save(
        address: address,
        lat: _mapLat,
        lng: _mapLon,
        scope: scope,
      );
    }
    ref.read(deliveryLocationProvider.notifier).state = DeliveryLocation(
      address: address,
      lat: _mapLat,
      lng: _mapLon,
    );
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final marker = _formattedAddress.trim().isEmpty
        ? null
        : YandexMapMarker(
            _mapLat,
            _mapLon,
            title: _placeName.trim().isEmpty
                ? _formattedAddress.trim()
                : _placeName.trim(),
            subtitle: _formattedAddress.trim(),
          );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Адрес доставки'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = 16.0;
            const topPadding = 12.0;
            const searchHeight = 56.0;
            const overlayGap = 8.0;
            const mapTop = topPadding + searchHeight + 12.0;

            return Stack(
              children: [
                Positioned.fill(
                  top: mapTop,
                  child: YandexMapView(
                    lat: _mapLat,
                    lng: _mapLon,
                    zoom: _mapZoom,
                    selectable: true,
                    markers: marker == null ? const [] : [marker],
                    userMarker: (_userLat != null && _userLon != null)
                        ? YandexMapMarker(
                            _userLat!,
                            _userLon!,
                            title: 'Мое местоположение',
                          )
                        : null,
                    onTap: _onMapTap,
                  ),
                ),
                Positioned(
                  top: topPadding,
                  left: horizontalPadding,
                  right: horizontalPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        elevation: 10,
                        shadowColor: const Color(0x22000000),
                        borderRadius: BorderRadius.circular(16),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textInputAction: TextInputAction.search,
                          onTapOutside: (_) => _searchFocusNode.unfocus(),
                          onChanged: _scheduleSearch,
                          onSubmitted: (_) => _runManualSearch(),
                          decoration: InputDecoration(
                            hintText: 'Поиск адреса',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _runManualSearch,
                                  ),
                          ),
                        ),
                      ),
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: overlayGap),
                        Material(
                          elevation: 10,
                          shadowColor: const Color(0x22000000),
                          borderRadius: BorderRadius.circular(16),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _suggestions.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final place = _suggestions[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.place_outlined,
                                      size: 18),
                                  title: Text(
                                    place.placeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    place.formattedAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black.withOpacity(0.55),
                                    ),
                                  ),
                                  onTap: () => _selectSuggestion(place),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  top: mapTop + 16,
                  child: _MapZoomControls(
                    onZoomIn: _zoomInMap,
                    onZoomOut: _zoomOutMap,
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_permissionDeniedForever)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextButton(
                            onPressed: openAppSettings,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Open Settings'),
                          ),
                        ),
                      Material(
                        color: Colors.white,
                        elevation: 8,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _locating ? null : _useCurrentLocation,
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: Center(
                              child: _locating || _resolving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location, size: 22),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _save,
            child: const Text('Сохранить адрес'),
          ),
        ),
      ),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _MapZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
            splashRadius: 20,
          ),
          Container(
            width: 36,
            height: 1,
            color: Colors.black.withOpacity(0.08),
          ),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}
