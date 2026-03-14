import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../../data/models/menu_models.dart';
import '../../core/format/currency.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/localization/category_localizer.dart';

class ProductListScreen extends ConsumerWidget {
  final int? categoryId;
  final List<int> productIds;
  final String? titleOverride;
  const ProductListScreen({
    super.key,
    this.categoryId,
    this.productIds = const [],
    this.titleOverride,
  });

  static const _bg = Color(0xFFF8F6F6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final menuAsync = ref.watch(menuProvider);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: menuAsync.when(
          data: (menu) {
            final category = _findCategory(menu.categories, categoryId);
            final hasProductFilter = productIds.isNotEmpty;
            final products = hasProductFilter
                ? _filterProductsByIds(menu.categories, productIds)
                : (category?.products ??
                    menu.categories.expand((c) => c.products).toList());
            final rawTitle = (titleOverride ?? '').trim();
            final displayTitle = rawTitle.isNotEmpty
                ? rawTitle
                : hasProductFilter
                    ? t.t('discount_products')
                    : category == null
                        ? t.t('menu')
                        : localizeCategoryName(category.name, t);
            return Column(
              children: [
                _Header(title: displayTitle, count: products.length),
                const SizedBox(height: 8),
                _Filters(),
                if (products.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        t.t('no_results'),
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) =>
                          _ProductCard(product: products[index]),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(t.t('generic_error'))),
        ),
      ),
      bottomNavigationBar: _BottomNav(current: 1),
    );
  }

  CategoryModel? _findCategory(List<CategoryModel> categories, int? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<ProductModel> _filterProductsByIds(
      List<CategoryModel> categories, List<int> ids) {
    final byId = <int, ProductModel>{};
    for (final category in categories) {
      for (final product in category.products) {
        byId[product.id] = product;
      }
    }
    final out = <ProductModel>[];
    final seen = <int>{};
    for (final id in ids) {
      if (seen.contains(id)) continue;
      final product = byId[id];
      if (product == null) continue;
      seen.add(id);
      out.add(product);
    }
    return out;
  }
}

class _Header extends StatelessWidget {
  final String title;
  final int count;
  const _Header({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          _RoundIcon(
              icon: Icons.arrow_back_ios_new, onTap: () => context.pop()),
          Expanded(
            child: Column(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                Text('$count ${t.t('items_available')}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9A9A9A))),
              ],
            ),
          ),
          _RoundIcon(
              icon: Icons.shopping_cart, onTap: () => context.push('/cart')),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(label: t.t('filter'), icon: Icons.tune, primary: true),
          const SizedBox(width: 10),
          _FilterChip(label: t.t('price'), icon: Icons.keyboard_arrow_down),
          const SizedBox(width: 10),
          _FilterChip(
              label: t.t('popularity'), icon: Icons.keyboard_arrow_down),
          const SizedBox(width: 10),
          _FilterChip(label: t.t('spicy'), icon: Icons.bolt),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  const _FilterChip(
      {required this.label, required this.icon, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final bg = primary ? const Color(0xFFEE482B) : Colors.white;
    final color = primary ? Colors.white : const Color(0xFF1B100D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = product.imageUrl;
    final favorites = ref.watch(favoritesProvider);
    final isSaved = favorites.contains(product.id);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 170,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  image: image == null || image.isEmpty
                      ? null
                      : DecorationImage(
                          image: NetworkImage(image), fit: BoxFit.cover),
                  color: Colors.black12,
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: InkWell(
                  onTap: () =>
                      ref.read(favoritesProvider.notifier).toggle(product.id),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Icon(
                      isSaved ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: const Color(0xFFEE482B),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(product.description ?? '',
                    style: const TextStyle(
                        color: Color(0xFF9A9A9A), fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      formatUzs(product.price),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFEE482B)),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => ref.read(cartProvider.notifier).add(product),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: const Color(0xFFEE482B),
                            borderRadius: BorderRadius.circular(22)),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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

class _BottomNav extends StatelessWidget {
  final int current;
  const _BottomNav({required this.current});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return BottomAppBar(
      child: SizedBox(
        height: 58,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
                icon: Icons.home,
                label: t.t('home'),
                active: current == 0,
                onTap: () => context.go('/home')),
            _NavItem(
                icon: Icons.explore,
                label: t.t('explore'),
                active: current == 1,
                onTap: () {}),
            _NavItem(
                icon: Icons.receipt_long,
                label: t.t('orders'),
                active: current == 2,
                onTap: () => context.push('/orders')),
            _NavItem(
                icon: Icons.person,
                label: t.t('profile'),
                active: current == 3,
                onTap: () => context.push('/profile')),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFEE482B) : const Color(0xFF9A9A9A);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
