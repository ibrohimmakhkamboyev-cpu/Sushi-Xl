import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/state/providers.dart';
import '../../core/localization/sushi_localizations.dart';

class OrderSuccessScreen extends ConsumerStatefulWidget {
  final int? orderId;
  const OrderSuccessScreen({super.key, this.orderId});

  @override
  ConsumerState<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends ConsumerState<OrderSuccessScreen> {
  Timer? _timer;

  static const _primary = Color(0xFFEE482B);
  static const _bgTop = Color(0xFFFFE4D6);
  static const _bgMid = Color(0xFFFF9D6E);
  static const _bgBottom = Color(0xFFFFF3EC);

  @override
  void initState() {
    super.initState();
    if (!useBackend || widget.orderId == null) return;
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      ref.invalidate(orderFetchProvider(widget.orderId!));
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
    final orderAsync = widget.orderId != null
        ? ref.watch(orderFetchProvider(widget.orderId!))
        : null;
    final order =
        orderAsync?.maybeWhen(data: (value) => value, orElse: () => null);
    final orderStatus = order?.status ?? 'preparing';
    final activeIndex = _activeStatusIndex(orderStatus);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgMid, _bgBottom],
            stops: [0.0, 0.42, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  if (Navigator.of(context).canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/home');
                                  }
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                              Expanded(
                                child: Text(
                                  t.t('order_success_title'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 19,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 40),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFCA2C),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFFFFCA2C).withOpacity(0.42),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            t.t('order_success_hero_title'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.t('order_success_hero_subtitle'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A3D180A),
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFEFE9),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _localizedStatus(t, orderStatus),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: _primary,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '#SXL-${order?.id ?? widget.orderId ?? '--'}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF241714),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _StatusProgressBar(activeIndex: activeIndex),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _ProgressLabel(
                                      text: t.t('status_accepted'),
                                      active: activeIndex >= 0,
                                      current: activeIndex == 0,
                                    ),
                                    _ProgressLabel(
                                      text: t.t('status_preparing'),
                                      active: activeIndex >= 1,
                                      current: activeIndex == 1,
                                    ),
                                    _ProgressLabel(
                                      text: t.t('status_on_the_way'),
                                      active: activeIndex >= 2,
                                      current: activeIndex == 2,
                                    ),
                                    _ProgressLabel(
                                      text: t.t('status_delivered'),
                                      active: activeIndex >= 3,
                                      current: activeIndex == 3,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFE76A31), Color(0xFFFC9458)],
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x2EEE482B),
                                  blurRadius: 14,
                                  offset: Offset(0, 7),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.t('order_success_prepared_for_you'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.asset(
                                    'assets/images/discount3.png',
                                    width: 150,
                                    height: 118,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () => context.go('/home'),
                            child: Text(t.t('back_to_menu')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  int _activeStatusIndex(String raw) {
    switch (raw) {
      case 'pending':
      case 'sent':
      case 'telegram_only':
        return 0;
      case 'accepted':
      case 'preparing':
        return 1;
      case 'on_the_way':
        return 2;
      case 'delivered':
      case 'completed':
        return 3;
      default:
        return 1;
    }
  }

  String _localizedStatus(SushiLocalizations t, String raw) {
    switch (raw) {
      case 'pending':
        return t.t('status_pending');
      case 'accepted':
        return t.t('status_preparing');
      case 'sent':
        return t.t('status_sent');
      case 'preparing':
        return t.t('status_preparing');
      case 'on_the_way':
        return t.t('status_on_the_way');
      case 'delivered':
        return t.t('status_delivered');
      case 'completed':
        return t.t('status_completed');
      case 'cancelled':
        return t.t('status_cancelled');
      case 'telegram_only':
        return t.t('status_telegram_only');
      default:
        return raw;
    }
  }
}

class _StatusProgressBar extends StatelessWidget {
  final int activeIndex;
  const _StatusProgressBar({required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7DFDB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ((activeIndex + 1) / 4).clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEE482B),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: List.generate(4, (index) {
              final active = index <= activeIndex;
              return Expanded(
                child: Center(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? const Color(0xFFEE482B)
                          : const Color(0xFFE7DFDB),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ProgressLabel extends StatelessWidget {
  final String text;
  final bool active;
  final bool current;

  const _ProgressLabel({
    required this.text,
    required this.active,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: active ? const Color(0xFF463A35) : const Color(0xFF756C67),
          fontWeight: current ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
