import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cache/location_cache.dart';
import '../../core/cache/session_cache.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/state/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final session = ref.watch(userSessionProvider);
    final photoPath = ref.watch(profilePhotoProvider);
    final locale = ref.watch(localeProvider);
    final historyAsync = session == null
        ? null
        : ref.watch(orderHistoryProvider(session.userId));
    final hasPhoto = photoPath != null &&
        photoPath.isNotEmpty &&
        File(photoPath).existsSync();
    final fallbackAvatar = session?.gender == 'female'
        ? 'assets/images/profile_female.png'
        : 'assets/images/profile_default.png';
    final fullName = session?.fullName.trim() ?? '';
    final phone = session?.phone.trim() ?? '';
    final isGuest = fullName.isEmpty && phone.isEmpty;
    final displayName = fullName.isNotEmpty ? fullName : t.t('guest');
    final displayPhone = phone.isNotEmpty ? phone : null;

    final activeOrderId = historyAsync?.maybeWhen(
      data: (items) {
        for (final item in items) {
          final value = item.status.toLowerCase();
          final isPast = value.contains('deliver') ||
              value.contains('cancel') ||
              value.contains('complete') ||
              value.contains('done');
          if (!isPast) return item.id;
        }
        return null;
      },
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FA),
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: _ProfileBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFFEE482B),
                        size: 30,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        t.t('profile'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF231816),
                        ),
                      ),
                    ),
                    if (isGuest)
                      _ProfileHeaderButton(
                        onTap: () => context.push('/onboarding'),
                      )
                    else
                      _ProfileTopIcon(
                        icon: Icons.edit,
                        onTap: () => context.push('/profile-edit'),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Center(
                  child: Column(
                    children: <Widget>[
                      _ProfileAvatar(
                        imageProvider: hasPhoto
                            ? FileImage(File(photoPath))
                            : AssetImage(fallbackAvatar) as ImageProvider,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF231816),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (displayPhone != null)
                        Text(
                          displayPhone,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF847C80),
                          ),
                        )
                      else
                        Text(
                          t.t('register_reminder'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF847C80),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _ProfileActionCard(
                        title: t.t('profile_track_order'),
                        subtitle: t.t('profile_track_order_subtitle'),
                        illustration: const _TrackOrderArt(),
                        onTap: () {
                          if (activeOrderId != null) {
                            context.push('/tracking?orderId=$activeOrderId');
                          } else {
                            context.push('/orders');
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ProfileActionCard(
                        title: t.t('profile_my_orders'),
                        subtitle: t.t('profile_my_orders_subtitle'),
                        illustration: const _MyOrdersArt(),
                        onTap: () => context.push('/orders?tab=past'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ProfileMenuTile(
                  icon: Icons.favorite,
                  label: t.t('favorites'),
                  onTap: () => context.push('/saved'),
                ),
                const SizedBox(height: 14),
                _ProfileMenuTile(
                  icon: Icons.language,
                  label: t.t('language'),
                  trailing: locale.languageCode.toUpperCase(),
                  onTap: () => _showLanguageSheet(context, ref),
                ),
                const SizedBox(height: 14),
                _ProfileMenuTile(
                  icon: Icons.headset_mic,
                  label: t.t('support_help'),
                  onTap: () => context.push('/support'),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(62),
                    foregroundColor: const Color(0xFFEE482B),
                    backgroundColor: Colors.white.withOpacity(0.34),
                    side: const BorderSide(color: Color(0x55EE482B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: isGuest
                      ? () => context.push('/onboarding')
                      : session == null
                          ? null
                          : () async {
                              final scoped = _locationScope(session);
                              if (scoped != null) {
                                await LocationCache().clear(scope: scoped);
                              }
                              await LocationCache().clear(scope: 'guest');
                              await ref.read(cartProvider.notifier).clear();
                              await ref
                                  .read(favoritesProvider.notifier)
                                  .clear();
                              await ref
                                  .read(localOrderHistoryProvider.notifier)
                                  .clear();
                              ref
                                  .read(deliveryLocationProvider.notifier)
                                  .state = null;
                              final guest = UserSession.guest(
                                preferredLang:
                                    ref.read(localeProvider).languageCode,
                              );
                              ref.read(userSessionProvider.notifier).state =
                                  guest;
                              await SessionCache().save(guest.toJson());
                            },
                  icon: Icon(
                    isGuest
                        ? Icons.person_add_alt_1_rounded
                        : Icons.logout_outlined,
                    size: 28,
                  ),
                  label: Text(isGuest ? t.t('register') : t.t('logout')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _LangOption(
                  title: 'O‘zbekcha',
                  subtitle: 'UZ',
                  onTap: () => _applyLanguage(ref, const Locale('uz')),
                ),
                _LangOption(
                  title: 'Русский',
                  subtitle: 'RU',
                  onTap: () => _applyLanguage(ref, const Locale('ru')),
                ),
                _LangOption(
                  title: 'English',
                  subtitle: 'EN',
                  onTap: () => _applyLanguage(ref, const Locale('en')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyLanguage(WidgetRef ref, Locale locale) async {
    ref.read(localeProvider.notifier).state = locale;
    ref.invalidate(menuProvider);
    final session = ref.read(userSessionProvider);
    if (session != null) {
      final updated = UserSession(
        userId: session.userId,
        phone: session.phone,
        fullName: session.fullName,
        preferredLang: locale.languageCode,
        gender: session.gender,
        accessToken: session.accessToken,
      );
      ref.read(userSessionProvider.notifier).state = updated;
      await SessionCache().save(updated.toJson());
    }
  }

  String? _locationScope(UserSession? session) {
    if (session == null) return null;
    if (session.userId > 0) return 'uid_${session.userId}';
    final phone = session.phone.trim();
    if (phone.isNotEmpty) return 'phone_$phone';
    return null;
  }
}

class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFF9F8FB),
                Color(0xFFF5F2F4),
              ],
            ),
          ),
        ),
        Positioned(
          left: -118,
          top: 210,
          child: _glowRibbon(
            width: 360,
            height: 86,
            rotation: -0.22,
            opacity: 0.22,
          ),
        ),
        Positioned(
          left: -42,
          top: 428,
          child: _glowRibbon(
            width: 250,
            height: 52,
            rotation: 0.18,
            opacity: 0.16,
          ),
        ),
        Positioned(
          right: -8,
          top: 96,
          child: Transform.rotate(
            angle: 0.74,
            child: const SizedBox(
              width: 138,
              height: 138,
              child: _TopChopsticksArt(),
            ),
          ),
        ),
        Positioned(
          top: 84,
          right: 40,
          child: _softOrb(
            size: 124,
            opacity: 0.14,
          ),
        ),
        Positioned(
          top: 604,
          left: 26,
          right: 26,
          child: _glowRibbon(
            width: 0,
            height: 42,
            rotation: 0.0,
            opacity: 0.12,
            stretch: true,
          ),
        ),
        Positioned(
          bottom: 0,
          left: -16,
          child: _BottomNigiri(alignRight: false),
        ),
        Positioned(
          bottom: 0,
          right: -12,
          child: _BottomNigiri(alignRight: true),
        ),
        const Positioned(
          top: 154,
          right: 84,
          child: _GlowArcCluster(),
        ),
      ],
    );
  }

  Widget _glowRibbon({
    required double width,
    required double height,
    required double rotation,
    double opacity = 0.18,
    bool stretch = false,
  }) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        width: stretch ? null : width,
        height: height,
        constraints:
            stretch ? const BoxConstraints(minWidth: 220, maxWidth: 520) : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            colors: <Color>[
              const Color(0xFFFFA45C).withOpacity(0),
              const Color(0xFFFFB66E).withOpacity(opacity),
              const Color(0xFFFFF0CB).withOpacity(opacity * 0.9),
              const Color(0xFFFFE0AE).withOpacity(0),
            ],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFFFBF7C).withOpacity(opacity * 0.72),
              blurRadius: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _softOrb({
    required double size,
    required double opacity,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFE8D7).withOpacity(opacity),
      ),
    );
  }
}

class _GlowArcCluster extends StatelessWidget {
  const _GlowArcCluster();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 156,
        height: 92,
        child: CustomPaint(
          painter: _GlowArcPainter(),
        ),
      ),
    );
  }
}

class _GlowArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcs = <(double, double, double)>[
      (8, 1.25, 0.16),
      (20, 1.15, 0.13),
      (34, 1.05, 0.10),
    ];

    for (final (inset, sweep, opacity) in arcs) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(rect.right - 110, rect.center.dy),
          Offset(rect.right, rect.center.dy),
          <Color>[
            const Color(0x00FFD19E),
            const Color(0x55FFD39F).withOpacity(opacity / 0.16),
            const Color(0x00FFE8C4),
          ],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawArc(
        Rect.fromLTWH(
            inset, inset / 2, size.width - inset, size.height - inset),
        -0.52,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProfileTopIcon extends StatelessWidget {
  const _ProfileTopIcon({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.84),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF9E7E77).withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF1B1010), size: 26),
      ),
    );
  }
}

class _ProfileHeaderButton extends StatelessWidget {
  const _ProfileHeaderButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.86),
          foregroundColor: const Color(0xFF1B1010),
          elevation: 0,
          minimumSize: const Size(52, 52),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: const Icon(Icons.person_add_alt_1_rounded, size: 24),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageProvider,
  });

  final ImageProvider imageProvider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      height: 156,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            Colors.white.withOpacity(0.98),
            const Color(0xFFFBE5DE),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFB67A).withOpacity(0.30),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.92), width: 5),
          ),
          child: CircleAvatar(
            backgroundColor: const Color(0xFFE6EEF8),
            backgroundImage: imageProvider,
          ),
        ),
      ),
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget illustration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleFontSize = _titleFontSize(title);
    final subtitleFontSize = _subtitleFontSize(subtitle);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 208,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withOpacity(0.68),
              Colors.white.withOpacity(0.42),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.76)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFE5BAAF).withOpacity(0.24),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        const Color(0xFFFFF8F6).withOpacity(0.20),
                        Colors.transparent,
                        const Color(0xFFFFE4D8).withOpacity(0.26),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -14,
                left: -20,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFE0D4).withOpacity(0.34),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFE9DE).withOpacity(0.60),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 92,
                      child: Center(child: illustration),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF231815),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 3,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        height: 1.4,
                        color: const Color(0xFF56454A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _titleFontSize(String value) {
    final length = value.trim().length;
    if (length >= 18) return 15;
    if (length >= 12) return 16;
    return 18;
  }

  double _subtitleFontSize(String value) {
    final length = value.trim().length;
    if (length >= 48) return 10.5;
    if (length >= 34) return 11;
    return 12;
  }
}

class _TrackOrderArt extends StatelessWidget {
  const _TrackOrderArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned(
          top: 2,
          right: 18,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFC987),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFFC987).withOpacity(0.34),
                  blurRadius: 20,
                ),
              ],
            ),
            child: const Icon(Icons.schedule_rounded,
                size: 30, color: Color(0xFFB45721)),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: -0.08,
              child: Container(
                width: 108,
                height: 94,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFFFFD2A8),
                      Color(0xFFE18758),
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFE38F5F).withOpacity(0.26),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: <Widget>[
                    Positioned(
                      top: 8,
                      left: 34,
                      right: 34,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFB06A4E),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 18,
                      left: 22,
                      child: _CartEye(),
                    ),
                    const Positioned(
                      bottom: 18,
                      right: 22,
                      child: _CartEye(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartEye extends StatelessWidget {
  const _CartEye();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.elliptical(10, 6)),
      ),
    );
  }
}

class _MyOrdersArt extends StatelessWidget {
  const _MyOrdersArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          left: 6,
          top: 36,
          child: Transform.rotate(
            angle: -0.28,
            child: const SizedBox(
              width: 42,
              height: 62,
              child: _TopChopsticksArt(compact: true),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 6,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFFFC18C),
                  Color(0xFFE46B3E),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFF9C62).withOpacity(0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    const Icon(Icons.access_time_rounded,
                        color: Color(0xFFE46B3E), size: 42),
                    Transform.rotate(
                      angle: 0.64,
                      child: Container(
                        width: 4,
                        height: 20,
                        margin: const EdgeInsets.only(left: 12, top: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE46B3E),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          bottom: 0,
          child: Transform.rotate(
            angle: -0.36,
            child: Container(
              width: 96,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFFFFB29B),
                    Color(0xFFF47A55),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFF08F70).withOpacity(0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.84),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.88)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFD9B3A5).withOpacity(0.14),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: const Color(0xFFEE482B), size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF221715),
                ),
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Color(0xFF8E8180),
                  ),
                ),
              ),
            const Icon(Icons.chevron_right_rounded,
                size: 34, color: Color(0xFF544448)),
          ],
        ),
      ),
    );
  }
}

class _TopChopsticksArt extends StatelessWidget {
  const _TopChopsticksArt({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 60.0 : 126.0;
    final width = compact ? 36.0 : 88.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: compact ? 8 : 18,
            child: _stick(height: height - 6),
          ),
          Positioned(
            left: compact ? 18 : 42,
            top: compact ? 2 : 6,
            child: _stick(height: height - 2),
          ),
        ],
      ),
    );
  }

  Widget _stick({required double height}) {
    return Container(
      width: 6,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF6E3F29),
            Color(0xFF2C170F),
          ],
        ),
      ),
    );
  }
}

class _BottomNigiri extends StatelessWidget {
  const _BottomNigiri({required this.alignRight});

  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: alignRight ? 0.16 : -0.18,
      child: SizedBox(
        width: 124,
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned(
              bottom: 0,
              child: Container(
                width: 92,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF7F4),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
            Positioned(
              top: 8,
              child: Container(
                width: 98,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFFFFB69A),
                      Color(0xFFF16D46),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            Positioned(
              bottom: 18,
              child: Container(
                width: 14,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF7EB35C),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  const _LangOption({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing:
          Text(subtitle, style: const TextStyle(color: Color(0xFF8E8180))),
      onTap: () {
        onTap();
        Navigator.of(context).pop();
      },
    );
  }
}
