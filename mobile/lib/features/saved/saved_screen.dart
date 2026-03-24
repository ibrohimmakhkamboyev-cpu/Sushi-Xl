import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/currency.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/state/providers.dart';
import '../../core/widgets/remote_image_box.dart';
import '../../data/models/menu_models.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  static const _pageBackground = Color(0xFFF7EEEC);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final favorites = ref.watch(favoritesProvider);
    final cart = ref.watch(cartProvider);
    final menuAsync = ref.watch(menuProvider);

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          t.t('saved'),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: Color(0xFF231815),
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF231815),
            size: 28,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: menuAsync.when(
        data: (menu) {
          final items = _savedProducts(menu.categories, favorites);
          if (items.isEmpty) {
            return const _SavedEmptyState();
          }

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const _SavedPageBackground(),
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final product = items[index];
                  return _SavedCard(product: product, cart: cart);
                },
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final t = SushiLocalizations.of(context);
          return Center(child: Text(t.t('generic_error')));
        },
      ),
    );
  }

  List<ProductModel> _savedProducts(
    List<CategoryModel> categories,
    Set<int> ids,
  ) {
    if (ids.isEmpty) return <ProductModel>[];
    return categories
        .expand((c) => c.products)
        .where((p) => ids.contains(p.id))
        .toList();
  }
}

class _SavedEmptyState extends StatelessWidget {
  const _SavedEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _SavedPageBackground(),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 22, 32),
            child: Align(
              alignment: Alignment(0, -0.05),
              child: _SavedMessageCard(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedPageBackground extends StatelessWidget {
  const _SavedPageBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.78),
          radius: 1.08,
          colors: <Color>[
            Color(0xFFF7F1F2),
            Color(0xFFF7DAD5),
            Color(0xFFF4B8B0),
          ],
          stops: <double>[0.0, 0.58, 1.0],
        ),
      ),
      child: const _SavedBackgroundArt(),
    );
  }
}

class _SavedBackgroundArt extends StatelessWidget {
  const _SavedBackgroundArt();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: _SavedTexture()),
          _softCircle(top: -22, left: -26, size: 168, opacity: 0.20),
          _softCircle(top: 54, left: 34, size: 42, opacity: 0.24),
          _softCircle(top: 94, left: 46, size: 66, opacity: 0.14),
          _softCircle(top: 16, right: -26, size: 186, opacity: 0.15),
          _softCircle(top: 304, left: -34, size: 132, opacity: 0.17),
          _softCircle(bottom: 64, left: -28, size: 128, opacity: 0.14),
          _softCircle(bottom: -14, right: -28, size: 134, opacity: 0.12),
          const Positioned(
            left: 0,
            top: 132,
            child: _BubbleTrail(
              rotation: -0.30,
              spacing: 22,
              count: 7,
              startSize: 16,
            ),
          ),
          const Positioned(
            right: 20,
            top: 48,
            child: _BubbleTrail(
              rotation: 0.12,
              spacing: 16,
              count: 6,
              startSize: 10,
            ),
          ),
          const Positioned(
            right: 0,
            top: 300,
            child: _BubbleTrail(
              rotation: 0.48,
              spacing: 18,
              count: 8,
              startSize: 10,
            ),
          ),
          const Positioned(
            left: 180,
            bottom: 168,
            child: _BubbleTrail(
              rotation: -0.62,
              spacing: 24,
              count: 6,
              startSize: 10,
            ),
          ),
          const Positioned(
            top: 48,
            right: 24,
            child: _NigiriDecoration(),
          ),
          const Positioned(
            left: 16,
            bottom: 112,
            child: _MakiDecoration(),
          ),
          const Positioned(
            right: -2,
            bottom: 44,
            child: _ChopsticksDecoration(),
          ),
        ],
      ),
    );
  }

  Widget _softCircle({
    double? top,
    double? right,
    double? bottom,
    double? left,
    required double size,
    required double opacity,
  }) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      ),
    );
  }
}

class _SavedTexture extends StatelessWidget {
  const _SavedTexture();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SavedTexturePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _SavedTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..style = PaintingStyle.fill;
    final random = math.Random(12);

    for (var i = 0; i < 950; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final radius = 0.4 + random.nextDouble() * 1.4;
      canvas.drawCircle(Offset(dx, dy), radius, fill);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BubbleTrail extends StatelessWidget {
  const _BubbleTrail({
    required this.rotation,
    required this.spacing,
    required this.count,
    required this.startSize,
  });

  final double rotation;
  final double spacing;
  final int count;
  final double startSize;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(count, (index) {
          final size = startSize - index * 0.8;
          return Padding(
            padding: EdgeInsets.only(bottom: spacing / 2),
            child: Opacity(
              opacity: math.max(0.16, 0.64 - index * 0.08),
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

class _SavedMessageCard extends StatelessWidget {
  const _SavedMessageCard();

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 356),
      padding: const EdgeInsets.fromLTRB(30, 34, 30, 34),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withOpacity(0.58),
            Colors.white.withOpacity(0.34),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.42),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFDA9A94).withOpacity(0.16),
            blurRadius: 36,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 16,
            sigmaY: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.bookmark_border_rounded,
                size: 56,
                color: Color(0xFF3A2D2B),
              ),
              const SizedBox(height: 20),
              Text(
                t.t('saved_empty_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3A2B28),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t.t('saved_empty_subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF7B6B67),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NigiriDecoration extends StatelessWidget {
  const _NigiriDecoration();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.22,
      child: SizedBox(
        width: 172,
        height: 128,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned(
              bottom: 20,
              child: Container(
                width: 110,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFFFDF7F5),
                      Color(0xFFF6ECE8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFA5706F).withOpacity(0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _RicePainter(),
                ),
              ),
            ),
            Positioned(
              top: 26,
              child: Container(
                width: 118,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFFFFB7A1),
                      Color(0xFFFA7C63),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFDD7C69).withOpacity(0.34),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _SalmonStripePainter(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MakiDecoration extends StatelessWidget {
  const _MakiDecoration();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.36,
      child: SizedBox(
        width: 148,
        height: 148,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: <Color>[
                    Color(0xFF4D3B4B),
                    Color(0xFF241A22),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF432C3F).withOpacity(0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
            ),
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: Color(0xFFFDFBFB),
                shape: BoxShape.circle,
              ),
              child: CustomPaint(
                painter: _MakiFillPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChopsticksDecoration extends StatelessWidget {
  const _ChopsticksDecoration();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.38,
      child: SizedBox(
        width: 116,
        height: 244,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 30,
              child: _stick(),
            ),
            Positioned(
              left: 56,
              top: 8,
              child: _stick(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stick() {
    return Container(
      width: 16,
      height: 228,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFFFFF3EA),
            Color(0xFFF8D4BF),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFE7A393).withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
    );
  }
}

class _RicePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFF4EBE7);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 9; col++) {
        final dx = 14 + col * 10.5 + (row.isEven ? 0 : 3);
        final dy = 10 + row * 7.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(dx, dy), width: 8, height: 5),
            const Radius.circular(4),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SalmonStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.46)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 4; i++) {
      final startX = 24 + i * 20;
      canvas.drawLine(
        Offset(startX.toDouble(), 8),
        Offset(startX - 10, size.height - 8),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MakiFillPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rice = Paint()..color = const Color(0xFFF6F1EF);
    final salmon = Paint()..color = const Color(0xFFFFA480);
    final cucumber = Paint()..color = const Color(0xFF80B56C);
    final cream = Paint()..color = const Color(0xFFF8EEDD);

    canvas.drawCircle(center, 41, rice);
    canvas.drawCircle(center.translate(-10, -6), 12, salmon);
    canvas.drawCircle(center.translate(12, -8), 10, cream);
    canvas.drawCircle(center.translate(0, 12), 13, cucumber);
    canvas.drawCircle(
        center.translate(-2, 1), 9, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SavedCard extends ConsumerWidget {
  const _SavedCard({
    required this.product,
    required this.cart,
  });

  final ProductModel product;
  final CartState cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = product.imageUrl;
    final qty = _qtyForProduct(cart, product.id);
    return Stack(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF3D7D1)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFD9A09B).withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              RemoteImageBox(
                imageUrl: image,
                width: 82,
                height: 82,
                borderRadius: BorderRadius.circular(18),
                backgroundColor: const Color(0xFFF1E5E1),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF2D1F1C),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatUzs(product.price),
                      style: const TextStyle(
                        color: Color(0xFFEE482B),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              _QtyControl(
                qty: qty,
                onMinus: () {
                  if (qty <= 0) return;
                  if (qty == 1) {
                    ref
                        .read(cartProvider.notifier)
                        .removeItem(product, modifiers: const []);
                  } else {
                    ref.read(cartProvider.notifier).updateQty(
                      product,
                      qty - 1,
                      modifiers: const [],
                    );
                  }
                },
                onPlus: () {
                  if (qty == 0) {
                    ref
                        .read(cartProvider.notifier)
                        .add(product, modifiers: const []);
                  } else {
                    ref.read(cartProvider.notifier).updateQty(
                      product,
                      qty + 1,
                      modifiers: const [],
                    );
                  }
                },
              ),
            ],
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: InkWell(
            onTap: () =>
                ref.read(favoritesProvider.notifier).toggle(product.id),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite,
                size: 15,
                color: Color(0xFFEE482B),
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _qtyForProduct(CartState cart, int productId) {
    var total = 0;
    for (final item in cart.items) {
      if (item.product.id == productId && item.modifiers.isEmpty) {
        total += item.qty;
      }
    }
    return total;
  }
}

class _QtyControl extends StatelessWidget {
  const _QtyControl({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });

  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8EFEC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _QtyButton(icon: Icons.remove, onTap: onMinus, filled: false),
          SizedBox(
            width: 28,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _QtyButton(icon: Icons.add, onTap: onPlus, filled: true),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFEE482B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 16,
          color: filled ? Colors.white : const Color(0xFF2F2522),
        ),
      ),
    );
  }
}
