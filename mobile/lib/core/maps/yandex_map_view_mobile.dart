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
  int _cameraRequestId = 0;

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
    unawaited(_applyCamera(animated: true));
  }

  ym.CameraPosition _buildCameraPosition() {
    return ym.CameraPosition(
      target: ym.Point(latitude: widget.lat, longitude: widget.lng),
      zoom: widget.zoom,
    );
  }

  Future<void> _applyCamera({required bool animated}) async {
    final controller = _controller;
    if (controller == null) return;

    final requestId = ++_cameraRequestId;
    Future<void> moveOnce({
      required Duration delay,
      required bool animate,
    }) async {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!mounted || requestId != _cameraRequestId) return;
      final activeController = _controller;
      if (activeController == null) return;
      try {
        await activeController.moveCamera(
          ym.CameraUpdate.newCameraPosition(_cameraPosition),
          animation: animate
              ? const ym.MapAnimation(
                  type: ym.MapAnimationType.smooth,
                  duration: 0.25,
                )
              : null,
        );
      } catch (_) {
        // Ignore transient platform-view timing issues and let later retries win.
      }
    }

    await moveOnce(delay: Duration.zero, animate: animated);
    unawaited(
        moveOnce(delay: const Duration(milliseconds: 120), animate: false));
    unawaited(
        moveOnce(delay: const Duration(milliseconds: 420), animate: false));
  }

  List<ym.MapObject> _buildMapObjects() {
    final objects = <ym.MapObject>[];

    for (var i = 0; i < widget.markers.length; i++) {
      final marker = widget.markers[i];
      final point = ym.Point(latitude: marker.lat, longitude: marker.lng);
      objects.addAll(_buildSelectedMarkerObjects(point, i));
    }

    final user = widget.userMarker;
    if (user != null) {
      final point = ym.Point(latitude: user.lat, longitude: user.lng);
      objects.addAll(_buildUserMarkerObjects(point));
    }

    return objects;
  }

  List<ym.MapObject> _buildSelectedMarkerObjects(ym.Point point, int index) {
    final idPrefix = 'selected_${index}_${point.latitude}_${point.longitude}';
    return [
      ym.CircleMapObject(
        mapId: ym.MapObjectId('${idPrefix}_glow'),
        circle: ym.Circle(center: point, radius: 24),
        fillColor: const Color(0x26EE482B),
        strokeColor: const Color(0x44EE482B),
        strokeWidth: 2,
        zIndex: 24,
      ),
      ym.CircleMapObject(
        mapId: ym.MapObjectId('${idPrefix}_ring'),
        circle: ym.Circle(center: point, radius: 10),
        fillColor: Colors.white,
        strokeColor: Colors.white,
        strokeWidth: 0,
        zIndex: 25,
      ),
      ym.CircleMapObject(
        mapId: ym.MapObjectId('${idPrefix}_core'),
        circle: ym.Circle(center: point, radius: 5.5),
        fillColor: const Color(0xFFEE482B),
        strokeColor: const Color(0xFFEE482B),
        strokeWidth: 0,
        zIndex: 26,
      ),
    ];
  }

  List<ym.MapObject> _buildUserMarkerObjects(ym.Point point) {
    return [
      ym.CircleMapObject(
        mapId: const ym.MapObjectId('user_marker_glow'),
        circle: ym.Circle(center: point, radius: 36),
        fillColor: const Color(0x242196F3),
        strokeColor: const Color(0x552196F3),
        strokeWidth: 2,
        zIndex: 18,
      ),
      ym.CircleMapObject(
        mapId: const ym.MapObjectId('user_marker_ring'),
        circle: ym.Circle(center: point, radius: 13),
        fillColor: Colors.white,
        strokeColor: Colors.white,
        strokeWidth: 0,
        zIndex: 19,
      ),
      ym.CircleMapObject(
        mapId: const ym.MapObjectId('user_marker_core'),
        circle: ym.Circle(center: point, radius: 6),
        fillColor: const Color(0xFF2196F3),
        strokeColor: const Color(0xFF2196F3),
        strokeWidth: 0,
        zIndex: 20,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ym.YandexMap(
        mapType: ym.MapType.vector,
        fastTapEnabled: true,
        mode2DEnabled: true,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        zoomGesturesEnabled: true,
        scrollGesturesEnabled: true,
        mapObjects: _buildMapObjects(),
        onMapCreated: (controller) async {
          _controller = controller;
          await _applyCamera(animated: false);
        },
        onMapTap: widget.selectable
            ? (point) => widget.onTap?.call(point.latitude, point.longitude)
            : null,
      ),
    );
  }
}
