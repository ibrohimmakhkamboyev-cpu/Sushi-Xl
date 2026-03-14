import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:async';

import '../../core/state/providers.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/config.dart';
import '../../core/maps/yandex_map_view.dart';
import '../../core/maps/yandex_map_types.dart';
import '../../data/models/order_models.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  final int? orderId;
  const TrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!useBackend) return;
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final id = widget.orderId;
      if (id != null) {
        ref.invalidate(orderFetchProvider(id));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    if (widget.orderId == null) {
      return Scaffold(body: Center(child: Text(t.t('order_not_found'))));
    }
    if (!useBackend) {
      final loc = ref.watch(deliveryLocationProvider);
      final markers = <YandexMapMarker>[
        const YandexMapMarker(restaurantLat, restaurantLng),
      ];
      var centerLat = restaurantLat;
      var centerLng = restaurantLng;
      if (loc != null) {
        centerLat = loc.lat;
        centerLng = loc.lng;
        markers.add(YandexMapMarker(loc.lat, loc.lng));
      }
      final fallbackOrder = OrderResponse(
        id: widget.orderId!,
        status: 'telegram_only',
        paymentStatus: 'pending',
      );
      return Scaffold(
        appBar: AppBar(title: Text(t.t('tracking'))),
        body: _TrackingBody(
          order: fallbackOrder,
          markers: markers,
          centerLat: centerLat,
          centerLng: centerLng,
          infoMessage: t.t('tracking_backend_offline'),
        ),
      );
    }
    final orderAsync = ref.watch(orderFetchProvider(widget.orderId!));
    final session = ref.watch(userSessionProvider);
    final addressesAsync =
        session == null ? null : ref.watch(addressesProvider(session.userId));
    return Scaffold(
      appBar: AppBar(title: Text(t.t('tracking'))),
      body: orderAsync.when(
        data: (order) {
          double centerLat = restaurantLat;
          double centerLng = restaurantLng;
          List<YandexMapMarker> markers = [
            YandexMapMarker(restaurantLat, restaurantLng)
          ];
          if (addressesAsync != null) {
            return addressesAsync.when(
              data: (items) {
                if (items.isNotEmpty) {
                  final first = items.firstWhere(
                    (e) => e.lat != null && e.lng != null,
                    orElse: () => items.first,
                  );
                  if (first.lat != null && first.lng != null) {
                    centerLat = first.lat!;
                    centerLng = first.lng!;
                    markers.add(YandexMapMarker(first.lat!, first.lng!));
                  }
                }
                return _TrackingBody(
                  order: order,
                  markers: markers,
                  centerLat: centerLat,
                  centerLng: centerLng,
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => _TrackingBody(
                order: order,
                markers: markers,
                centerLat: centerLat,
                centerLng: centerLng,
                infoMessage: t.t('tracking_address_offline'),
              ),
            );
          }
          return _TrackingBody(
              order: order,
              markers: markers,
              centerLat: centerLat,
              centerLng: centerLng);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          if (_isBackendUnavailable(err)) {
            final fallbackOrder = OrderResponse(
              id: widget.orderId!,
              status: 'telegram_only',
              paymentStatus: 'pending',
            );
            return _TrackingBody(
              order: fallbackOrder,
              markers: [const YandexMapMarker(restaurantLat, restaurantLng)],
              centerLat: restaurantLat,
              centerLng: restaurantLng,
              infoMessage: t.t('tracking_backend_offline'),
            );
          }
          return Center(child: Text(t.t('generic_error')));
        },
      ),
    );
  }

  bool _isBackendUnavailable(Object err) {
    if (err is! DioException) return false;
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout;
  }
}

class _TrackingBody extends StatelessWidget {
  final OrderResponse order;
  final List<YandexMapMarker> markers;
  final double centerLat;
  final double centerLng;
  final String? infoMessage;

  const _TrackingBody({
    required this.order,
    required this.markers,
    required this.centerLat,
    required this.centerLng,
    this.infoMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final localizedStatus = _localizedStatus(t, order.status);
    final localizedPayment = _localizedPaymentStatus(t, order.paymentStatus);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: YandexMapView(
                      lat: centerLat,
                      lng: centerLng,
                      zoom: 13,
                      markers: markers,
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${t.t('status')}: $localizedStatus',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t.t('order')} #${order.id}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${t.t('payment')}: $localizedPayment'),
                if (order.posterOrderId != null)
                  Text('${t.t('poster_id')}: ${order.posterOrderId}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            infoMessage ?? t.t('live_courier_not_available'),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _StatusTimeline(status: order.status),
        ],
      ),
    );
  }

  String _localizedStatus(SushiLocalizations t, String raw) {
    switch (raw) {
      case 'pending':
        return t.t('status_pending');
      case 'accepted':
      case 'new':
        return t.t('status_preparing');
      case 'sent':
        return t.t('status_sent');
      case 'preparing':
        return t.t('status_preparing');
      case 'on_the_way':
        return t.t('status_on_the_way');
      case 'delivered':
        return t.t('status_delivered');
      case 'telegram_only':
        return t.t('status_telegram_only');
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  String _localizedPaymentStatus(SushiLocalizations t, String raw) {
    switch (raw) {
      case 'pending':
        return t.t('payment_pending');
      case 'paid':
        return t.t('payment_paid');
      case 'unpaid':
        return t.t('payment_unpaid');
      default:
        return raw;
    }
  }
}

class _StatusTimeline extends StatelessWidget {
  final String status;
  const _StatusTimeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final steps = ['pending', 'sent', 'preparing', 'on_the_way', 'delivered'];
    final normalized = switch (status) {
      'telegram_only' => 'pending',
      'accepted' || 'new' => 'preparing',
      _ => status,
    };
    final current = steps.indexOf(normalized);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps.asMap().entries.map((entry) {
        final idx = entry.key;
        final label = _stepLabel(t, entry.value);
        final done = current >= idx && current != -1;
        return Row(
          children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        );
      }).toList(),
    );
  }

  String _stepLabel(SushiLocalizations t, String code) {
    switch (code) {
      case 'pending':
        return t.t('status_pending');
      case 'sent':
        return t.t('status_sent');
      case 'preparing':
        return t.t('status_preparing');
      case 'on_the_way':
        return t.t('status_on_the_way');
      case 'delivered':
        return t.t('status_delivered');
      default:
        return code.replaceAll('_', ' ');
    }
  }
}
