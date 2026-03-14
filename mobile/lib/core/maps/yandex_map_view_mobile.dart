import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart' as ym;

import 'yandex_map_types.dart';

class YandexMapViewImpl extends StatefulWidget {
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
  State<YandexMapViewImpl> createState() => _YandexMapViewImplState();
}

class _YandexMapViewImplState extends State<YandexMapViewImpl> {
  ym.YandexMapController? _controller;
  late ym.CameraPosition _cameraPosition;

  @override
  void initState() {
    super.initState();
    _cameraPosition = _buildCameraPosition();
  }

  @override
  void didUpdateWidget(covariant YandexMapViewImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cameraChanged = oldWidget.lat != widget.lat ||
        oldWidget.lng != widget.lng ||
        oldWidget.zoom != widget.zoom;
    if (!cameraChanged) return;

    final next = _buildCameraPosition();
    _cameraPosition = next;
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.moveCamera(
        ym.CameraUpdate.newCameraPosition(next),
        animation: const ym.MapAnimation(
          type: ym.MapAnimationType.smooth,
          duration: 0.25,
        ),
      ),
    );
  }

  ym.CameraPosition _buildCameraPosition() {
    return ym.CameraPosition(
      target: ym.Point(latitude: widget.lat, longitude: widget.lng),
      zoom: widget.zoom,
    );
  }

  List<ym.MapObject> _buildMapObjects() {
    final objects = <ym.MapObject>[];

    for (var i = 0; i < widget.markers.length; i++) {
      final marker = widget.markers[i];
      objects.add(
        ym.PlacemarkMapObject(
          mapId: ym.MapObjectId('marker_${i}_${marker.lat}_${marker.lng}'),
          point: ym.Point(latitude: marker.lat, longitude: marker.lng),
          opacity: 1,
          zIndex: 10,
        ),
      );
    }

    final user = widget.userMarker;
    if (user != null) {
      objects.add(
        ym.PlacemarkMapObject(
          mapId: const ym.MapObjectId('user_marker'),
          point: ym.Point(latitude: user.lat, longitude: user.lng),
          opacity: 0.9,
          zIndex: 20,
        ),
      );
    }

    return objects;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ym.YandexMap(
        mapType: ym.MapType.vector,
        fastTapEnabled: true,
        mode2DEnabled: false,
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: true,
        zoomGesturesEnabled: true,
        scrollGesturesEnabled: true,
        mapObjects: _buildMapObjects(),
        onMapCreated: (controller) async {
          _controller = controller;
          await controller.moveCamera(
            ym.CameraUpdate.newCameraPosition(_cameraPosition),
          );
        },
        onMapTap: widget.selectable
            ? (point) => widget.onTap?.call(point.latitude, point.longitude)
            : null,
      ),
    );
  }
}
