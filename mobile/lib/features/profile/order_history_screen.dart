import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/sushi_localizations.dart';
import '../../core/state/providers.dart';
import '../../data/models/cart_models.dart';
import '../../data/models/menu_models.dart';
import '../../data/models/order_history_models.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({
    super.key,
    this.initialTab = OrderHistoryTab.active,
  });

  final OrderHistoryTab initialTab;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

enum OrderHistoryTab {
  active,
  past,
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  late OrderHistoryTab _selectedTab = widget.initialTab;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final session = ref.read(userSessionProvider);
      if (session == null || session.userId <= 0) return;
      ref.invalidate(orderHistoryProvider(session.userId));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final session = ref.watch(userSessionProvider);
    if (session == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F2F1),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const _OrderHistoryContentBackground(),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: _OrderHistoryHeader(
                      selectedTab: _selectedTab,
                      onChanged: (tab) => setState(() => _selectedTab = tab),
                      onBack: () => _handleBack(context),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        t.t('login_required'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final historyAsync = ref.watch(orderHistoryProvider(session.userId));
    final menuAsync = ref.watch(menuProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F2F1),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const _OrderHistoryContentBackground(),
          SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: _OrderHistoryHeader(
                    selectedTab: _selectedTab,
                    onChanged: (tab) => setState(() => _selectedTab = tab),
                    onBack: () => _handleBack(context),
                  ),
                ),
                Expanded(
                  child: historyAsync.when(
                    data: (items) {
                      final activeOrders = items.where(_isActive).toList();
                      final pastOrders = items.where(_isPast).toList();
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: _selectedTab == OrderHistoryTab.active
                            ? _buildActiveContent(context, activeOrders)
                            : _buildPastContent(
                                context, ref, menuAsync, pastOrders),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _buildActiveContent(
                        context, const <OrderHistoryItem>[]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/profile');
    }
  }

  Widget _buildActiveContent(
    BuildContext context,
    List<OrderHistoryItem> activeOrders,
  ) {
    if (activeOrders.isNotEmpty) {
      return ListView.separated(
        key: const ValueKey<String>('active-orders'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: activeOrders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) =>
            _LiveOrderCard(order: activeOrders[index]),
      );
    }

    return const SizedBox.expand(
      key: ValueKey<String>('active-empty'),
      child: _OrderHistoryEmptyState(),
    );
  }

  Widget _buildPastContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<MenuResponse> menuAsync,
    List<OrderHistoryItem> pastOrders,
  ) {
    if (pastOrders.isEmpty) {
      return const SizedBox.expand(
        key: ValueKey<String>('past-empty'),
        child: _PastOrderEmptyState(),
      );
    }

    return ListView.separated(
      key: const ValueKey<String>('past-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: pastOrders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _PastOrderCard(
        order: pastOrders[index],
        onReorder: () async {
          final menu = menuAsync.valueOrNull;
          if (menu == null) return;
          final detail =
              await ref.read(orderDetailProvider(pastOrders[index].id).future);
          final cartItems = detail.items
              .map((d) {
                final product = _findProduct(menu.categories, d.productId);
                if (product == null) return null;
                final modifiers = d.modifiers
                    .map(
                      (m) => CartModifierSelection(
                        modifierId: m.modifierId,
                        price: m.price,
                      ),
                    )
                    .toList();
                return CartItemModel(
                  product: product,
                  qty: d.qty,
                  modifiers: modifiers,
                );
              })
              .whereType<CartItemModel>()
              .toList();
          ref.read(cartProvider.notifier).setFromOrder(cartItems);
          if (context.mounted) {
            context.push('/cart');
          }
        },
      ),
    );
  }

  bool _isActive(OrderHistoryItem item) {
    final status = item.status.toLowerCase();
    return !(status.contains('deliver') ||
        status.contains('cancel') ||
        status.contains('complete') ||
        status.contains('done'));
  }

  bool _isPast(OrderHistoryItem item) => !_isActive(item);

  ProductModel? _findProduct(List<CategoryModel> categories, int id) {
    for (final category in categories) {
      for (final product in category.products) {
        if (product.id == id) return product;
      }
    }
    return null;
  }
}

class _OrderHistoryContentBackground extends StatelessWidget {
  const _OrderHistoryContentBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.58),
          radius: 1.32,
          colors: <Color>[
            Color(0xFFF9F2F1),
            Color(0xFFF5D7D2),
            Color(0xFFF0B9B1),
          ],
          stops: <double>[0, 0.64, 1],
        ),
      ),
      child: _OrderGlowBackdrop(),
    );
  }
}

class _OrderHistoryHeader extends StatelessWidget {
  const _OrderHistoryHeader({
    required this.selectedTab,
    required this.onChanged,
    required this.onBack,
  });

  final OrderHistoryTab selectedTab;
  final ValueChanged<OrderHistoryTab> onChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _OrderBackButton(onTap: onBack),
        const SizedBox(width: 10),
        Expanded(
          child: _OrderTabSwitcher(
            selectedTab: selectedTab,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _OrderBackButton extends StatelessWidget {
  const _OrderBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0ECEB),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const SizedBox(
          width: 50,
          height: 50,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 22,
            color: Color(0xFF221614),
          ),
        ),
      ),
    );
  }
}

class _OrderTabSwitcher extends StatelessWidget {
  const _OrderTabSwitcher({
    required this.selectedTab,
    required this.onChanged,
  });

  final OrderHistoryTab selectedTab;
  final ValueChanged<OrderHistoryTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      height: 56,
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0ECEB),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _OrderTabButton(
              label: t.t('active_tab'),
              selected: selectedTab == OrderHistoryTab.active,
              onTap: () => onChanged(OrderHistoryTab.active),
            ),
          ),
          Expanded(
            child: _OrderTabButton(
              label: t.t('past_tab'),
              selected: selectedTab == OrderHistoryTab.past,
              onTap: () => onChanged(OrderHistoryTab.past),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTabButton extends StatelessWidget {
  const _OrderTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7E2E2) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFF231815) : const Color(0xFF9F9796),
          ),
        ),
      ),
    );
  }
}

class _OrderHistoryEmptyState extends StatelessWidget {
  const _OrderHistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Align(
            alignment: const Alignment(0, -0.02),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 372),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Colors.white.withOpacity(0.46),
                    Colors.white.withOpacity(0.26),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.38)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFD99A93).withOpacity(0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        height: 194,
                        child: _OrderEmptyHeroArt(),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        t.t('no_active_orders'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF332622),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.t('no_orders_subtitle'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.5,
                          color: Color(0xFF7B6965),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF04A4A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onPressed: () => context.go('/home'),
                          child: Text(t.t('browse_menu')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PastOrderEmptyState extends StatelessWidget {
  const _PastOrderEmptyState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: Opacity(
          opacity: 0.82,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 28,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Colors.white.withOpacity(0.26),
                  Colors.white.withOpacity(0.12),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.24)),
            ),
            child: const SizedBox(
              height: 190,
              child: _OrderEmptyHeroArt(),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderGlowBackdrop extends StatelessWidget {
  const _OrderGlowBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const <Widget>[
        Positioned(
          top: 34,
          left: -30,
          child: _SoftDisc(size: 152, opacity: 0.16),
        ),
        Positioned(
          top: 84,
          left: 46,
          child: _SoftDisc(size: 40, opacity: 0.22),
        ),
        Positioned(
          top: 118,
          left: 62,
          child: _SoftDisc(size: 62, opacity: 0.12),
        ),
        Positioned(
          top: 22,
          right: -26,
          child: _SoftDisc(size: 198, opacity: 0.14),
        ),
        Positioned(
          top: 104,
          right: 34,
          child: _BubbleSwarm(angle: 0.14),
        ),
        Positioned(
          top: 154,
          left: 8,
          child: _BubbleSwarm(angle: -0.34, count: 8),
        ),
        Positioned(
          bottom: 132,
          right: 8,
          child: _BubbleSwarm(angle: 0.46, count: 8),
        ),
        Positioned(
          bottom: 58,
          left: -36,
          child: _SoftDisc(size: 142, opacity: 0.14),
        ),
        Positioned(
          bottom: 176,
          left: 34,
          child: _SoftDisc(size: 58, opacity: 0.10),
        ),
        Positioned(
          bottom: 132,
          right: 36,
          child: _SoftDisc(size: 74, opacity: 0.08),
        ),
        Positioned(
          bottom: -14,
          right: -30,
          child: _SoftDisc(size: 146, opacity: 0.12),
        ),
        Positioned(
          bottom: 22,
          left: 132,
          child: _BubbleSwarm(angle: -0.54, count: 7),
        ),
      ],
    );
  }
}

class _SoftDisc extends StatelessWidget {
  const _SoftDisc({
    required this.size,
    required this.opacity,
  });

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

class _BubbleSwarm extends StatelessWidget {
  const _BubbleSwarm({
    this.angle = 0,
    this.count = 6,
  });

  final double angle;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(count, (index) {
          final size = 11 - index * 0.8;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Opacity(
              opacity: math.max(0.16, 0.62 - index * 0.07),
              child: Container(
                width: math.max(4, size),
                height: math.max(4, size),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _OrderEmptyHeroArt extends StatelessWidget {
  const _OrderEmptyHeroArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: const <Widget>[
        Positioned(
          top: 8,
          left: 40,
          child: _OrderBagDecoration(),
        ),
        Positioned(
          top: 44,
          right: 44,
          child: _OrderMakiDecoration(),
        ),
        Positioned(
          top: 48,
          right: 12,
          child: _OrderChopsticksDecoration(),
        ),
      ],
    );
  }
}

class _OrderBagDecoration extends StatelessWidget {
  const _OrderBagDecoration();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.16,
      child: Container(
        width: 126,
        height: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFFFD4B2),
              Color(0xFFE38B65),
            ],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFE0916C).withOpacity(0.26),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: 10,
              left: 40,
              right: 40,
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFB97054),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const Positioned.fill(
              child: Center(
                child: Text(
                  'SUSHI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderMakiDecoration extends StatelessWidget {
  const _OrderMakiDecoration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const RadialGradient(
          colors: <Color>[
            Color(0xFF4B3844),
            Color(0xFF241A22),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF4A3543).withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFFDFBFB),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: const <Widget>[
              Positioned(
                  top: 16,
                  left: 20,
                  child: _MakiDot(color: Color(0xFFFFA480), size: 16)),
              Positioned(
                  top: 20,
                  right: 18,
                  child: _MakiDot(color: Color(0xFFF5E0C5), size: 14)),
              Positioned(
                  bottom: 16,
                  child: _MakiDot(color: Color(0xFF88BB72), size: 18)),
              _MakiDot(color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _MakiDot extends StatelessWidget {
  const _MakiDot({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _OrderChopsticksDecoration extends StatelessWidget {
  const _OrderChopsticksDecoration();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.56,
      child: SizedBox(
        width: 64,
        height: 122,
        child: Stack(
          children: const <Widget>[
            Positioned(left: 12, child: _Chopstick()),
            Positioned(left: 34, top: 4, child: _Chopstick()),
          ],
        ),
      ),
    );
  }
}

class _Chopstick extends StatelessWidget {
  const _Chopstick();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 114,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFFFFF3EA),
            Color(0xFFF7D0BD),
          ],
        ),
      ),
    );
  }
}

class _LiveOrderCard extends StatelessWidget {
  const _LiveOrderCard({
    required this.order,
  });

  final OrderHistoryItem order;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final step = _statusStep(order.status);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0DBD7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFD7A29A).withOpacity(0.16),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFECE7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    t.t(_statusLabel(order.status)),
                    style: const TextStyle(
                      color: Color(0xFFEE482B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${order.id}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF231815),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _formatDate(order.createdAt),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF7A6A66),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                _ProgressDot(active: step >= 0),
                _ProgressLine(active: step >= 1),
                _ProgressDot(active: step >= 1),
                _ProgressLine(active: step >= 2),
                _ProgressDot(active: step >= 2),
                _ProgressLine(active: step >= 3),
                _ProgressDot(active: step >= 3),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _ProgressLabel(t.t('status_accepted')),
                _ProgressLabel(t.t('status_preparing')),
                _ProgressLabel(t.t('status_on_the_way')),
                _ProgressLabel(t.t('status_delivered')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('cancel')) return 'status_cancelled';
    if (value.contains('deliver') ||
        value.contains('complete') ||
        value.contains('done')) {
      return 'status_delivered';
    }
    if (value.contains('way') || value.contains('courier')) {
      return 'status_on_the_way';
    }
    if (value.contains('prepar') || value.contains('cook')) {
      return 'status_preparing';
    }
    if (value.contains('pending') ||
        value.contains('sent') ||
        value.contains('accept') ||
        value.contains('new')) {
      return 'status_preparing';
    }
    return 'status_preparing';
  }

  int _statusStep(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('deliver') ||
        value.contains('complete') ||
        value.contains('done')) {
      return 3;
    }
    if (value.contains('way') || value.contains('courier')) return 2;
    if (value.contains('prepar') || value.contains('cook')) return 1;
    if (value.contains('pending') ||
        value.contains('sent') ||
        value.contains('accept') ||
        value.contains('new')) {
      return 1;
    }
    if (value.contains('cancel')) {
      return 0;
    }
    return 1;
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ProgressDot extends StatelessWidget {
  const _ProgressDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEE482B) : const Color(0xFFE0D9D7),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 3,
        color: active ? const Color(0xFFF3A090) : const Color(0xFFE8E1DF),
      ),
    );
  }
}

class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF7B6A66),
        ),
      ),
    );
  }
}

class _PastOrderCard extends StatelessWidget {
  const _PastOrderCard({
    required this.order,
    required this.onReorder,
  });

  final OrderHistoryItem order;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF0DBD7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFD7A29A).withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFFFE4DE),
                  Color(0xFFF5C8C0),
                ],
              ),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFFEE482B),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${t.t('order')} #${order.id}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF231815),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDate(order.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7C6D68),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.t(_pastStatus(order.status)),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEE482B),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onReorder,
            child: Text(
              t.t('reorder'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEE482B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _pastStatus(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('cancel')) return 'status_cancelled';
    if (value.contains('deliver') ||
        value.contains('complete') ||
        value.contains('done')) {
      return 'status_delivered';
    }
    return 'status_completed';
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}
