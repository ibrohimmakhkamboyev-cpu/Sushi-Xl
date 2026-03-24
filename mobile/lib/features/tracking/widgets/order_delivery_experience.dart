import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format/currency.dart';
import '../../../core/localization/sushi_localizations.dart';
import '../../../core/orders/order_status.dart';

class OrderExperienceItem {
  final String title;
  final int qty;
  final double lineTotal;
  final String? imageUrl;

  const OrderExperienceItem({
    required this.title,
    required this.qty,
    required this.lineTotal,
    this.imageUrl,
  });
}

class OrderDeliveryExperience extends StatelessWidget {
  const OrderDeliveryExperience({
    super.key,
    required this.headerTitle,
    required this.leadingIcon,
    required this.onLeadingTap,
    required this.status,
    required this.paymentStatus,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.etaLabel,
    required this.items,
    required this.totalPrice,
    required this.onBackToMenu,
    required this.onOpenChat,
    this.orderId,
    this.posterOrderId,
    this.infoMessage,
    this.supportPhone = '',
    this.callLabel,
    this.chatLabel,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.loading = false,
  });

  final String headerTitle;
  final IconData leadingIcon;
  final VoidCallback onLeadingTap;
  final String status;
  final String paymentStatus;
  final String heroTitle;
  final String heroSubtitle;
  final String etaLabel;
  final int? orderId;
  final String? posterOrderId;
  final String? infoMessage;
  final List<OrderExperienceItem> items;
  final double totalPrice;
  final String supportPhone;
  final String? callLabel;
  final String? chatLabel;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final VoidCallback onBackToMenu;
  final VoidCallback onOpenChat;
  final bool loading;

  static const _bg = Color(0xFFF8F3EF);

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final normalizedStatus = canonicalOrderStatus(status);
    final progress = _routeProgress(normalizedStatus);
    final statusLabel = t.t(_statusKey(normalizedStatus));
    final paymentLabel = _localizedPaymentStatus(t, paymentStatus);
    final resolvedCallLabel = (callLabel ?? '').trim().isEmpty
        ? t.t('call_support')
        : callLabel!.trim();
    final resolvedChatLabel = (chatLabel ?? '').trim().isEmpty
        ? t.t('chat_with_us')
        : chatLabel!.trim();

    return Scaffold(
      backgroundColor: _bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFFFFF4EC),
              Color(0xFFF8F3EF),
              Color(0xFFF6F1EC),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              _HeaderRow(
                title: headerTitle,
                leadingIcon: leadingIcon,
                onLeadingTap: onLeadingTap,
              ),
              const SizedBox(height: 16),
              _HeroCard(
                title: heroTitle,
                subtitle: heroSubtitle,
                statusLabel: statusLabel,
                paymentLabel: paymentLabel,
                orderId: orderId,
                posterOrderId: posterOrderId,
                loading: loading,
              ),
              const SizedBox(height: 14),
              _EtaCard(label: etaLabel),
              const SizedBox(height: 14),
              _ProgressCard(status: normalizedStatus),
              const SizedBox(height: 14),
              _RouteCard(progress: progress),
              const SizedBox(height: 14),
              _SummaryCard(items: items, totalPrice: totalPrice),
              if ((infoMessage ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _InlineInfoCard(message: infoMessage!.trim()),
              ],
              const SizedBox(height: 14),
              _SupportRow(
                callLabel: resolvedCallLabel,
                chatLabel: resolvedChatLabel,
                phoneNumber: supportPhone,
                onOpenChat: onOpenChat,
              ),
              const SizedBox(height: 14),
              const _BonusCard(),
              const SizedBox(height: 18),
              _BottomActions(
                primaryLabel: primaryActionLabel,
                onPrimaryAction: onPrimaryAction,
                secondaryLabel: t.t('back_to_menu'),
                onSecondaryAction: onBackToMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusKey(String normalizedStatus) {
    switch (normalizedStatus) {
      case 'accepted':
        return 'status_accepted';
      case 'preparing':
        return 'status_preparing';
      case 'on_the_way':
        return 'status_on_the_way';
      case 'delivered':
        return 'status_delivered';
      case 'cancelled':
        return 'status_cancelled';
      case 'telegram_only':
        return 'status_telegram_only';
      case 'pending':
      default:
        return 'status_pending';
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

  double _routeProgress(String normalizedStatus) {
    switch (normalizedStatus) {
      case 'accepted':
        return 0.18;
      case 'preparing':
        return 0.42;
      case 'on_the_way':
        return 0.74;
      case 'delivered':
        return 1;
      case 'pending':
      case 'telegram_only':
      case 'cancelled':
      default:
        return 0.1;
    }
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.title,
    required this.leadingIcon,
    required this.onLeadingTap,
  });

  final String title;
  final IconData leadingIcon;
  final VoidCallback onLeadingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassIconButton(icon: leadingIcon, onTap: onLeadingTap),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF161617),
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.paymentLabel,
    required this.loading,
    this.orderId,
    this.posterOrderId,
  });

  final String title;
  final String subtitle;
  final String statusLabel;
  final String paymentLabel;
  final int? orderId;
  final String? posterOrderId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF181A20), Color(0xFF27212A)],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22191614),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -28,
            child: Container(
              width: 132,
              height: 132,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x44FF8A4A), Color(0x00FF8A4A)],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _PulseSuccessBadge(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: loading ? 0.75 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFFD4C8C2),
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroMetaChip(
                    label: t.t('status'),
                    value: statusLabel,
                    tint: const Color(0x1FFF8C5E),
                  ),
                  _HeroMetaChip(
                    label: t.t('payment'),
                    value: paymentLabel,
                    tint: const Color(0x1F5BDBB1),
                  ),
                  if (orderId != null)
                    _HeroMetaChip(
                      label: t.t('order_id'),
                      value: '#$orderId',
                      tint: const Color(0x1F7E8DF4),
                    ),
                  if ((posterOrderId ?? '').trim().isNotEmpty)
                    _HeroMetaChip(
                      label: t.t('poster_id'),
                      value: posterOrderId!.trim(),
                      tint: const Color(0x1FFCCB5E),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5ED),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD6BF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14EE482B),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEE482B),
            ),
            child: const Icon(Icons.access_time_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.t('estimated_delivery_title'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Color(0xFF9A7D70),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF161617),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.status});

  final String status;

  static const _stages = <_StageData>[
    _StageData(
        'confirmed', Icons.check_circle_rounded, 'order_stage_confirmed'),
    _StageData('cooking', Icons.ramen_dining_rounded, 'order_stage_cooking'),
    _StageData(
        'on_the_way', Icons.delivery_dining_rounded, 'order_stage_on_the_way'),
    _StageData('delivered', Icons.place_rounded, 'order_stage_delivered'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _currentStageIndex(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SushiLocalizations.of(context).t('tracking_progress_title'),
            style: const TextStyle(
              color: Color(0xFF161617),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = constraints.maxWidth - 52;
              final fraction = _progressFraction(current);
              return SizedBox(
                height: 86,
                child: Stack(
                  children: [
                    Positioned(
                      left: 26,
                      right: 26,
                      top: 16,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAE4DF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 26,
                      top: 16,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOutCubic,
                        width: progressWidth * fraction,
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: <Color>[
                              Color(0xFFFFB37C),
                              Color(0xFFEE482B)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _stages.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final stage = entry.value;
                        final done = idx <= current;
                        final currentStage = idx == current;
                        return _StageNode(
                          icon: stage.icon,
                          label:
                              SushiLocalizations.of(context).t(stage.labelKey),
                          done: done,
                          current: currentStage,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _currentStageIndex(String normalizedStatus) {
    switch (normalizedStatus) {
      case 'delivered':
        return 3;
      case 'on_the_way':
        return 2;
      case 'preparing':
        return 1;
      case 'accepted':
      case 'pending':
      case 'telegram_only':
      case 'cancelled':
      default:
        return 0;
    }
  }

  double _progressFraction(int stageIndex) {
    if (stageIndex <= 0) return 0.08;
    return stageIndex / (_stages.length - 1);
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.t('delivery_route_title'),
            style: const TextStyle(
              color: Color(0xFF161617),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress.clamp(0, 1)),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedValue, _) {
                    final horizontal =
                        (constraints.maxWidth - 62) * animatedValue;
                    final bounce = math.sin(animatedValue * math.pi) * 10;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RoutePainter(progress: animatedValue),
                          ),
                        ),
                        Positioned(
                          left: 22 + horizontal,
                          top: 32 - bounce,
                          child: Transform.rotate(
                            angle: 0.08,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFEE482B),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0x33EE482B),
                                    blurRadius: 12,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.delivery_dining_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: _RouteEndpoint(
                            icon: Icons.storefront_rounded,
                            label: t.t('delivery_route_restaurant'),
                            alignEnd: false,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _RouteEndpoint(
                            icon: Icons.location_on_rounded,
                            label: t.t('delivery_route_you'),
                            alignEnd: true,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.items,
    required this.totalPrice,
  });

  final List<OrderExperienceItem> items;
  final double totalPrice;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.t('order_summary'),
            style: const TextStyle(
              color: Color(0xFF161617),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Text(
              t.t('order_summary_empty'),
              style: const TextStyle(
                color: Color(0xFF7A6B65),
                fontSize: 14,
                height: 1.4,
              ),
            )
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SummaryRow(item: item),
                )),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFECE6E1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.t('total'),
                  style: const TextStyle(
                    color: Color(0xFF161617),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatUzs(totalPrice),
                style: const TextStyle(
                  color: Color(0xFFEE482B),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineInfoCard extends StatelessWidget {
  const _InlineInfoCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFDFC8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFEE482B), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7A6B65),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.callLabel,
    required this.chatLabel,
    required this.phoneNumber,
    required this.onOpenChat,
  });

  final String callLabel;
  final String chatLabel;
  final String phoneNumber;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SupportButton(
            icon: Icons.call_rounded,
            label: callLabel,
            tint: const Color(0xFFEE482B),
            onTap: () => _callSupport(context, phoneNumber: phoneNumber),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SupportButton(
            icon: Icons.chat_bubble_rounded,
            label: chatLabel,
            tint: const Color(0xFF111827),
            onTap: onOpenChat,
          ),
        ),
      ],
    );
  }

  Future<void> _callSupport(
    BuildContext context, {
    required String phoneNumber,
  }) async {
    final t = SushiLocalizations.of(context);
    final rawPhone = phoneNumber.trim();
    final dialablePhone = _normalizeDialablePhone(rawPhone);
    if (dialablePhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('support_call_failed'))),
      );
      return;
    }
    final launched = await _launchDialer(dialablePhone);
    if (launched || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: rawPhone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${t.t('support_call_failed')} ${t.t('support_call_copied')} $rawPhone',
        ),
      ),
    );
  }

  Future<bool> _launchDialer(String phoneNumber) async {
    final candidates = <Uri>[Uri.parse('tel:$phoneNumber')];
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      candidates.insert(0, Uri.parse('telprompt:$phoneNumber'));
    }
    for (final uri in candidates) {
      try {
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  String _normalizeDialablePhone(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty) return '';
    final hasLeadingPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return hasLeadingPlus ? '+$digits' : digits;
  }
}

class _BonusCard extends StatelessWidget {
  const _BonusCard();

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF0E5), Color(0xFFFFF8F3)],
        ),
        border: Border.all(color: const Color(0xFFFFD8C2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF161617),
            ),
            child: const Icon(Icons.local_offer_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.t('order_bonus_title'),
                  style: const TextStyle(
                    color: Color(0xFF161617),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.t('order_bonus_subtitle'),
                  style: const TextStyle(
                    color: Color(0xFF7A6B65),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.secondaryLabel,
    required this.onSecondaryAction,
    this.primaryLabel,
    this.onPrimaryAction,
  });

  final String? primaryLabel;
  final VoidCallback? onPrimaryAction;
  final String secondaryLabel;
  final VoidCallback onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final hasPrimary =
        (primaryLabel ?? '').trim().isNotEmpty && onPrimaryAction != null;
    return Column(
      children: [
        if (hasPrimary)
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: onPrimaryAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEE482B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(primaryLabel!),
            ),
          ),
        if (hasPrimary) const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: onSecondaryAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF161617),
              side: const BorderSide(color: Color(0xFFE3D7D0)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              backgroundColor: Colors.white.withOpacity(0.78),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(secondaryLabel),
          ),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.78),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: const Color(0xFF161617), size: 22),
        ),
      ),
    );
  }
}

class _PulseSuccessBadge extends StatefulWidget {
  const _PulseSuccessBadge();

  @override
  State<_PulseSuccessBadge> createState() => _PulseSuccessBadgeState();
}

class _PulseSuccessBadgeState extends State<_PulseSuccessBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1.04).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFC15C), Color(0xFFEE482B)],
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x44EE482B),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  const _HeroMetaChip({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD4C8C2),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.icon,
    required this.label,
    required this.done,
    required this.current,
  });

  final IconData icon;
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final fill = done ? const Color(0xFFEE482B) : const Color(0xFFF3ECE8);
    final iconColor = done ? Colors.white : const Color(0xFFA2928A);
    final textColor =
        current ? const Color(0xFF161617) : const Color(0xFF7A6B65);
    return SizedBox(
      width: 74,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: current ? 42 : 36,
            height: current ? 42 : 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: done ? const Color(0x00FFFFFF) : const Color(0xFFE3D7D0),
              ),
              boxShadow: current
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x22EE482B),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              height: 1.3,
              fontWeight: current ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteEndpoint extends StatelessWidget {
  const _RouteEndpoint({
    required this.icon,
    required this.label,
    required this.alignEnd,
  });

  final IconData icon;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFFECE6E1)),
          ),
          child: Icon(icon, color: const Color(0xFF161617), size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7A6B65),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.item});

  final OrderExperienceItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF2EA),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: item.imageUrl != null && item.imageUrl!.trim().isNotEmpty
              ? Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.set_meal_rounded,
                    color: Color(0xFFEE482B),
                  ),
                )
              : const Icon(
                  Icons.set_meal_rounded,
                  color: Color(0xFFEE482B),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  color: Color(0xFF161617),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'x${item.qty}',
                style: const TextStyle(
                  color: Color(0xFF7A6B65),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Text(
          formatUzs(item.lineTotal),
          style: const TextStyle(
            color: Color(0xFF161617),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: _cardDecoration(borderRadius: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: tint, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF161617),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(26, size.height * 0.55);
    final end = Offset(size.width - 26, size.height * 0.52);
    final control = Offset(size.width * 0.52, size.height * 0.14);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEAE4DF);
    canvas.drawPath(path, basePaint);

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final activePath =
        metric.extractPath(0, metric.length * progress.clamp(0, 1));
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFFFB37C), Color(0xFFEE482B)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(activePath, activePaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _StageData {
  const _StageData(this.code, this.icon, this.labelKey);

  final String code;
  final IconData icon;
  final String labelKey;
}

BoxDecoration _cardDecoration({
  double borderRadius = 28,
}) {
  return BoxDecoration(
    color: Colors.white.withOpacity(0.94),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: const Color(0xFFF0E8E3)),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color(0x12000000),
        blurRadius: 20,
        offset: Offset(0, 12),
      ),
    ],
  );
}
