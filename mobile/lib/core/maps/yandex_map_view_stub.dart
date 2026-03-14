import 'package:flutter/material.dart';
import '../localization/sushi_localizations.dart';
import 'yandex_map_types.dart';

class YandexMapViewImpl extends StatelessWidget {
  final double lat;
  final double lng;
  final double zoom;
  final bool selectable;
  final List<YandexMapMarker> markers;
  final YandexMapMarker? userMarker;
  final String? addressLabel;
  final void Function(double lat, double lng)? onTap;

  const YandexMapViewImpl({
    super.key,
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.selectable,
    required this.markers,
    this.userMarker,
    this.addressLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Text(t.t('map_not_supported_platform')),
    );
  }
}
