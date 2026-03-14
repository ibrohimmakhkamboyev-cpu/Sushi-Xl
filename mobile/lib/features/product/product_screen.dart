import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../../data/models/menu_models.dart';
import '../../data/models/cart_models.dart';
import '../../core/format/currency.dart';
import '../../core/localization/sushi_localizations.dart';

class ProductScreen extends ConsumerStatefulWidget {
  final int? productId;
  const ProductScreen({super.key, this.productId});

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  final Map<int, bool> _selected = {};
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final menuAsync = ref.watch(menuProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F6),
      body: menuAsync.when(
        data: (menu) {
          final product = _find(menu.categories, widget.productId);
          if (product == null) {
            return Center(child: Text(t.t('product_not_found')));
          }
          final total = _calcTotal(product);
          final image = product.imageUrl;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 280,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            image: image == null || image.isEmpty
                                ? null
                                : DecorationImage(
                                    image: NetworkImage(image),
                                    fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          top: MediaQuery.of(context).padding.top + 8,
                          child: _RoundIcon(
                              icon: Icons.arrow_back,
                              onTap: () => _handleBack(context)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(product.name,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w800)),
                          ),
                          Text(
                            formatUzs(product.price),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFEE482B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          _InfoChip(
                              icon: Icons.restaurant,
                              label: '8 ${t.t('pieces_label')}',
                              color: Color(0xFFFFE9D6)),
                          const _InfoChip(
                              icon: Icons.local_fire_department,
                              label: '320 kcal',
                              color: Color(0xFFFFE2E2)),
                          _InfoChip(
                              icon: Icons.eco,
                              label: t.t('fresh_raw'),
                              color: Color(0xFFE4F7E7)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(product.description ?? '',
                          style: const TextStyle(color: Color(0xFF7A7A7A))),
                    ),
                    const SizedBox(height: 18),
                    if (product.modifiers.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(t.t('addons_extras'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 8),
                      ...product.modifiers.map(
                        (m) => _AddonTile(
                          name: m.name,
                          price: m.price ?? 0,
                          selected: _selected[m.id] ?? false,
                          onTap: () => setState(() =>
                              _selected[m.id] = !(_selected[m.id] ?? false)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    _QtySelector(
                      qty: _qty,
                      onMinus: () =>
                          setState(() => _qty = (_qty - 1).clamp(1, 99)),
                      onPlus: () =>
                          setState(() => _qty = (_qty + 1).clamp(1, 99)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEE482B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            final mods = product.modifiers
                                .where((m) => _selected[m.id] ?? false)
                                .map((m) => CartModifierSelection(
                                      modifierId: m.id,
                                      price: m.price ?? 0,
                                    ))
                                .toList();
                            for (var i = 0; i < _qty; i += 1) {
                              ref
                                  .read(cartProvider.notifier)
                                  .add(product, modifiers: mods);
                            }
                            _handleBack(context);
                          },
                          child: Text(
                              '${t.t('add_to_cart')} • ${formatUzs(total)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(t.t('generic_error'))),
      ),
    );
  }

  double _calcTotal(ProductModel product) {
    final base = product.price ?? 0;
    final mods = product.modifiers
        .where((m) => _selected[m.id] ?? false)
        .fold<double>(0, (sum, m) => sum + (m.price ?? 0));
    return base + mods;
  }

  ProductModel? _find(List<CategoryModel> categories, int? id) {
    if (id == null) return null;
    for (final c in categories) {
      for (final p in c.products) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  void _handleBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
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
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFEE482B)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AddonTile extends StatelessWidget {
  final String name;
  final double price;
  final bool selected;
  final VoidCallback onTap;
  const _AddonTile(
      {required this.name,
      required this.price,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(price == 0 ? t.t('free') : '+${formatUzs(price)}',
                    style: const TextStyle(color: Color(0xFF9A9A9A))),
              ],
            ),
          ),
          InkWell(
            onTap: onTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFEE482B)
                    : const Color(0xFFF2F2F2),
                shape: BoxShape.circle,
              ),
              child: Icon(selected ? Icons.check : Icons.add,
                  color: selected ? Colors.white : const Color(0xFFEE482B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _QtySelector extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _QtySelector(
      {required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      width: 120,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDED))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          InkWell(
              onTap: onMinus,
              child: const Icon(Icons.remove, color: Color(0xFF6C6C6C))),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800)),
          InkWell(
              onTap: onPlus,
              child: const Icon(Icons.add, color: Color(0xFFEE482B))),
        ],
      ),
    );
  }
}
