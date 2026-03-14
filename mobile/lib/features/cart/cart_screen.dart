import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../../data/models/cart_models.dart';
import '../../data/models/menu_models.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/format/currency.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final total = ref.read(cartProvider.notifier).total();
    final menuAsync = ref.watch(menuProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F6),
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: t.t('cart')),
            Expanded(
              child: cart.items.isEmpty
                  ? Center(child: Text(t.t('cart_empty')))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 140),
                      children: [
                        _DeliveryProgress(),
                        ...cart.items.map(
                          (item) => _CartItemCard(item: item),
                        ),
                        menuAsync.when(
                          data: (menu) {
                            final products = menu.categories
                                .expand((c) => c.products)
                                .toList();
                            if (products.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _RecommendedSection(
                              title: t.t('recommended_products'),
                              products: products.take(6).toList(),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        _OrderSummary(total: total),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        enabled: cart.items.isNotEmpty,
        onCheckout: () => context.push('/checkout'),
      ),
    );
  }
}

class _RecommendedSection extends StatelessWidget {
  final String title;
  final List<ProductModel> products;
  const _RecommendedSection({required this.title, required this.products});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _RecommendedCard(product: products[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedCard extends ConsumerWidget {
  final ProductModel product;
  const _RecommendedCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = product.imageUrl;
    final cart = ref.watch(cartProvider);
    final item = cart.items.cast<CartItemModel?>().firstWhere(
          (e) => e?.product.id == product.id,
          orElse: () => null,
        );
    final qty = item?.qty ?? 0;
    return Container(
      width: 146,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 76,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              image: image == null || image.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(image), fit: BoxFit.cover),
              color: Colors.black12,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(formatUzs(product.price),
                style: const TextStyle(
                    color: Color(0xFFEE482B),
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: _MiniQty(
              qty: qty,
              onMinus: () {
                final mods = item?.modifiers ?? const <CartModifierSelection>[];
                if (qty <= 1) {
                  if (item != null) {
                    ref
                        .read(cartProvider.notifier)
                        .removeItem(product, modifiers: mods);
                  }
                } else {
                  ref
                      .read(cartProvider.notifier)
                      .updateQty(product, qty - 1, modifiers: mods);
                }
              },
              onPlus: () {
                final mods = item?.modifiers ?? const <CartModifierSelection>[];
                if (qty == 0) {
                  ref.read(cartProvider.notifier).add(product);
                } else {
                  ref
                      .read(cartProvider.notifier)
                      .updateQty(product, qty + 1, modifiers: mods);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniQty extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _MiniQty(
      {required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _MiniBtn(icon: Icons.remove, onTap: onMinus),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          _MiniBtn(icon: Icons.add, onTap: onPlus, filled: true),
        ],
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _MiniBtn(
      {required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFEE482B) : Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
        child:
            Icon(icon, size: 14, color: filled ? Colors.white : Colors.black87),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _RoundIcon(
              icon: Icons.arrow_back_ios_new, onTap: () => context.pop()),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 40, height: 40),
        ],
      ),
    );
  }
}

class _DeliveryProgress extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x11000000)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.t('free_delivery_progress'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9A9A9A)),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t.t('free_delivery_away'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFEE482B)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              value: 0.82,
              minHeight: 6,
              color: Color(0xFFEE482B),
              backgroundColor: Color(0xFFEDEDED),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemCard extends ConsumerWidget {
  final CartItemModel item;
  const _CartItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = item.product.imageUrl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 4),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              image: image == null || image.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(image), fit: BoxFit.cover),
              color: Colors.black12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(item.product.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      onPressed: () => ref
                          .read(cartProvider.notifier)
                          .removeItem(item.product, modifiers: item.modifiers),
                      icon: const Icon(Icons.delete, color: Color(0xFF9A9A9A)),
                    ),
                  ],
                ),
                Text(
                  formatUzs(item.product.price),
                  style: const TextStyle(
                      color: Color(0xFFEE482B), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _QtyControl(
                    qty: item.qty,
                    onMinus: () {
                      final next = (item.qty - 1).clamp(1, 99);
                      ref.read(cartProvider.notifier).updateQty(
                          item.product, next,
                          modifiers: item.modifiers);
                    },
                    onPlus: () {
                      final next = (item.qty + 1).clamp(1, 99);
                      ref.read(cartProvider.notifier).updateQty(
                          item.product, next,
                          modifiers: item.modifiers);
                    },
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

class _QtyControl extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _QtyControl(
      {required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyButton(icon: Icons.remove, onTap: onMinus, filled: false),
          SizedBox(
              width: 28,
              child: Text('$qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          _QtyButton(icon: Icons.add, onTap: onPlus, filled: true),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _QtyButton(
      {required this.icon, required this.onTap, required this.filled});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFEE482B) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            Icon(icon, size: 16, color: filled ? Colors.white : Colors.black87),
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final double total;
  const _OrderSummary({required this.total});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.t('order_summary'),
                style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: Color(0xFF9A9A9A),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _SummaryRow(label: t.t('subtotal'), value: formatUzs(total)),
            _SummaryRow(label: t.t('delivery_fee'), value: '15 000 UZS'),
            _SummaryRow(label: t.t('tax'), value: '0 UZS'),
            const Divider(),
            _SummaryRow(
                label: t.t('total'),
                value: formatUzs(total + 15000),
                strong: true,
                highlight: true),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final bool highlight;
  const _SummaryRow(
      {required this.label,
      required this.value,
      this.strong = false,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
      color: highlight ? const Color(0xFFEE482B) : const Color(0xFF1B100D),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF7A7A7A))),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onCheckout;
  const _BottomBar({required this.enabled, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Color(0x11000000), blurRadius: 8, offset: Offset(0, -2))
      ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEE482B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: enabled ? onCheckout : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text(t.t('proceed_checkout')),
            ),
          ),
          const SizedBox(height: 8),
          Text(t.t('terms_notice'),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9A9A9A))),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
