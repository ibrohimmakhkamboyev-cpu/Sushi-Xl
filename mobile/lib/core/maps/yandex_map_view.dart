import 'package:flutter/material.dart';
import 'yandex_map_types.dart';

import 'yandex_map_view_stub.dart'
    if (dart.library.html) 'yandex_map_view_web.dart'
    if (dart.library.io) 'yandex_map_view_mobile.dart';

class YandexMapView extends StatelessWidget {
  final double lat;
  final double lng;
  final double zoom;
  final bool selectable;
  final List<YandexMapMarker> markers;
  final YandexMapMarker? userMarker;
  final String? addressLabel;
  final void Function(double lat, double lng)? onTap;

  const YandexMapView({
    super.key,
    required this.lat,
    required this.lng,
    this.zoom = 14,
    this.selectable = false,
    this.markers = const [],
    this.userMarker,
    this.addressLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return YandexMapViewImpl(
      lat: lat,
      lng: lng,
      zoom: zoom,
      selectable: selectable,
      markers: markers,
      userMarker: userMarker,
      addressLabel: addressLabel,
      onTap: onTap,
    );
  }
}
