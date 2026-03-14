// ignore_for_file: undefined_prefixed_name
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../config.dart';
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
  late final String _viewType;
  html.IFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _viewType = 'yandex_map_${DateTime.now().microsecondsSinceEpoch}';
    _iframe = html.IFrameElement()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..src = _buildSrc();
    ui.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe!);
    _sub = html.window.onMessage.listen((event) {
      if (event.data is Map) {
        final data = event.data as Map;
        if (data['type'] == 'yamap_click' && data['id'] == _viewType) {
          final lat = (data['lat'] as num).toDouble();
          final lng = (data['lng'] as num).toDouble();
          widget.onTap?.call(lat, lng);
        }
      }
    });
  }

  String _buildSrc() {
    final markers = widget.markers.map((m) => '${m.lat},${m.lng}').join('|');
    final selectable = widget.selectable ? '1' : '0';
    final key = Uri.encodeComponent(yandexJsApiKey);
    final url =
        'yandex_map.html?key=$key&lat=${widget.lat}&lng=${widget.lng}&zoom=${widget.zoom}&selectable=$selectable&markers=$markers&id=$_viewType';
    return url;
  }

  @override
  void didUpdateWidget(covariant YandexMapViewImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.lat != widget.lat ||
        oldWidget.lng != widget.lng ||
        oldWidget.zoom != widget.zoom ||
        oldWidget.selectable != widget.selectable ||
        oldWidget.addressLabel != widget.addressLabel ||
        oldWidget.userMarker?.lat != widget.userMarker?.lat ||
        oldWidget.userMarker?.lng != widget.userMarker?.lng ||
        oldWidget.markers.length != widget.markers.length ||
        !_sameMarkers(oldWidget.markers, widget.markers);
    if (changed) {
      _iframe?.contentWindow?.postMessage({
        'type': 'yamap_update',
        'id': _viewType,
        'lat': widget.lat,
        'lng': widget.lng,
        'zoom': widget.zoom,
        'selectable': widget.selectable,
        'markers': widget.markers.map((m) => '${m.lat},${m.lng}').toList(),
      }, '*');
    }
  }

  bool _sameMarkers(List<YandexMapMarker> a, List<YandexMapMarker> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat ||
          a[i].lng != b[i].lng ||
          a[i].title != b[i].title ||
          a[i].subtitle != b[i].subtitle) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
