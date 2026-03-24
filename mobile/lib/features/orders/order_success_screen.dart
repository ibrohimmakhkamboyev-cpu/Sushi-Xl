import 'dart:async';

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
import '../tracking/widgets/order_delivery_experience.dart';

class OrderSuccessScreen extends ConsumerStatefulWidget {
  final int? orderId;
  const OrderSuccessScreen({super.key, this.orderId});

  @override
  ConsumerState<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends ConsumerState<OrderSuccessScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!useBackend || widget.orderId == null) return;
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      ref.invalidate(orderFetchProvider(widget.orderId!));
      ref.invalidate(orderDetailProvider(widget.orderId!));
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
    final locale = ref.watch(localeProvider);
    ref
        .read(supportCenterProvider.notifier)
        .ensureBackendSynced(lang: locale.languageCode);
    final supportConfig = ref.watch(supportCenterProvider);
    final menuAsync = ref.watch(menuProvider);
    final orderAsync = widget.orderId == null
        ? null
        : ref.watch(orderFetchProvider(widget.orderId!));
    final detailAsync = widget.orderId == null
        ? null
        : ref.watch(orderDetailProvider(widget.orderId!));

    final order = orderAsync?.valueOrNull ??
        OrderResponse(
          id: widget.orderId ?? 0,
          status: 'accepted',
          paymentStatus: 'pending',
        );
    final detail = detailAsync?.valueOrNull ??
        OrderDetailResponse(id: widget.orderId ?? 0, items: const []);
    final items = _buildExperienceItems(
      detail: detail,
      menu: menuAsync.valueOrNull,
      t: t,
    );
    final totalPrice =
        items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    return OrderDeliveryExperience(
      headerTitle: t.t('order_success_title'),
      leadingIcon: Icons.close_rounded,
      onLeadingTap: () {
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      status: order.status,
      paymentStatus: order.paymentStatus,
      heroTitle: t.t('order_success_hero_title'),
      heroSubtitle: t.t('order_success_hero_subtitle'),
      etaLabel: _etaLabel(t, order.status),
      orderId: widget.orderId,
      posterOrderId: order.posterOrderId,
      items: items,
      totalPrice: totalPrice,
      supportPhone: supportConfig.phoneNumber,
      callLabel: supportConfig.callLabel,
      chatLabel: supportConfig.chatLabel,
      onOpenChat: () => context.push('/support/chat'),
      primaryActionLabel: t.t('track_my_order'),
      onPrimaryAction: widget.orderId == null
          ? null
          : () => context.go('/tracking?orderId=${widget.orderId}'),
      onBackToMenu: () => context.go('/home'),
      loading:
          (orderAsync?.isLoading ?? false) || (detailAsync?.isLoading ?? false),
    );
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
