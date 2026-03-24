import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/orders/order_status.dart';
import '../../core/state/providers.dart';
import '../../data/models/menu_models.dart';
import '../../data/models/order_detail_models.dart';
import '../../data/models/order_models.dart';
import 'widgets/order_delivery_experience.dart';

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
        ref.invalidate(orderDetailProvider(id));
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
      return Scaffold(
        body: Center(child: Text(t.t('order_not_found'))),
      );
    }

    final locale = ref.watch(localeProvider);
    ref
        .read(supportCenterProvider.notifier)
        .ensureBackendSynced(lang: locale.languageCode);
    final supportConfig = ref.watch(supportCenterProvider);
    final orderAsync = ref.watch(orderFetchProvider(widget.orderId!));
    final detailAsync = ref.watch(orderDetailProvider(widget.orderId!));
    final menuAsync = ref.watch(menuProvider);

    final fallbackOrder = OrderResponse(
      id: widget.orderId!,
      status: 'telegram_only',
      paymentStatus: 'pending',
    );
    final order = orderAsync.valueOrNull ?? fallbackOrder;
    final detail = detailAsync.valueOrNull ??
        OrderDetailResponse(id: widget.orderId!, items: const []);
    final items = _buildExperienceItems(
      detail: detail,
      menu: menuAsync.valueOrNull,
      t: t,
    );
    final totalPrice =
        items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    return OrderDeliveryExperience(
      headerTitle: t.t('tracking'),
      leadingIcon: Icons.arrow_back_ios_new_rounded,
      onLeadingTap: () {
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/profile');
        }
      },
      status: order.status,
      paymentStatus: order.paymentStatus,
      heroTitle: _heroTitleForStatus(t, order.status),
      heroSubtitle: _heroSubtitleForStatus(t, order.status),
      etaLabel: _etaLabel(t, order.status),
      orderId: order.id,
      posterOrderId: order.posterOrderId,
      infoMessage: _infoMessage(
        t,
        orderAsync: orderAsync,
      ),
      items: items,
      totalPrice: totalPrice,
      supportPhone: supportConfig.phoneNumber,
      callLabel: supportConfig.callLabel,
      chatLabel: supportConfig.chatLabel,
      onOpenChat: () => context.push('/support/chat'),
      onBackToMenu: () => context.go('/home'),
      loading: orderAsync.isLoading || detailAsync.isLoading,
    );
  }

  String? _infoMessage(
    SushiLocalizations t, {
    required AsyncValue<OrderResponse> orderAsync,
  }) {
    if (!useBackend) return t.t('tracking_backend_offline');
    return orderAsync.whenOrNull(
      error: (err, _) =>
          _isBackendUnavailable(err) ? t.t('tracking_backend_offline') : null,
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

List<OrderExperienceItem> _buildExperienceItems({
  required OrderDetailResponse detail,
  required MenuResponse? menu,
  required SushiLocalizations t,
}) {
  if (detail.items.isEmpty) return const [];
  return detail.items.map((item) {
    final product = _findProduct(menu?.categories ?? const [], item.productId);
    final title = product?.name.trim().isNotEmpty == true
        ? product!.name.trim()
        : '${t.t('order_item_fallback')} #${item.productId}';
    final modifiersTotal = item.modifiers.fold<double>(
      0,
      (sum, modifier) => sum + modifier.price,
    );
    final lineTotal = (item.price + modifiersTotal) * item.qty;
    return OrderExperienceItem(
      title: title,
      qty: item.qty,
      lineTotal: lineTotal,
      imageUrl: product?.imageUrl,
    );
  }).toList(growable: false);
}

ProductModel? _findProduct(List<CategoryModel> categories, int id) {
  for (final category in categories) {
    for (final product in category.products) {
      if (product.id == id) return product;
    }
  }
  return null;
}

String _heroTitleForStatus(SushiLocalizations t, String rawStatus) {
  switch (canonicalOrderStatus(rawStatus)) {
    case 'delivered':
      return t.t('tracking_stage_delivered_title');
    case 'on_the_way':
      return t.t('tracking_stage_on_the_way_title');
    case 'preparing':
      return t.t('tracking_stage_cooking_title');
    case 'accepted':
    case 'pending':
    case 'telegram_only':
    case 'cancelled':
    default:
      return t.t('tracking_stage_confirmed_title');
  }
}

String _heroSubtitleForStatus(SushiLocalizations t, String rawStatus) {
  switch (canonicalOrderStatus(rawStatus)) {
    case 'delivered':
      return t.t('tracking_stage_delivered_subtitle');
    case 'on_the_way':
      return t.t('tracking_stage_on_the_way_subtitle');
    case 'preparing':
      return t.t('tracking_stage_cooking_subtitle');
    case 'accepted':
    case 'pending':
    case 'telegram_only':
    case 'cancelled':
    default:
      return t.t('tracking_stage_confirmed_subtitle');
  }
}

String _etaLabel(SushiLocalizations t, String rawStatus) {
  switch (canonicalOrderStatus(rawStatus)) {
    case 'delivered':
      return t.t('eta_arrived');
    case 'on_the_way':
      return t.t('eta_range_5_15');
    case 'preparing':
      return t.t('eta_range_15_25');
    case 'accepted':
    case 'pending':
    case 'telegram_only':
    case 'cancelled':
    default:
      return t.t('eta_range_25_35');
  }
}
