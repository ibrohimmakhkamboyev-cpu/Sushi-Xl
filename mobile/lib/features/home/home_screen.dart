import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/providers.dart';
import '../../data/models/menu_models.dart';
import '../../core/format/currency.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/localization/category_localizer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  static const _bg = Color(0xFFF8F6F6);
  int? _selectedCategoryId;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshRemoteHomeData();
    });
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _refreshRemoteHomeData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRemoteHomeData();
    }
  }

  void _refreshRemoteHomeData() {
    if (!mounted) return;
    ref.invalidate(menuProvider);
    ref.invalidate(adminAdsProvider);
    ref.invalidate(backendMailingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final menuAsync = ref.watch(menuProvider);
    final adsAsync = ref.watch(adminAdsProvider);
    final discountAds =
        adsAsync.maybeWhen(data: (v) => v, orElse: () => const <AdminAdItem>[]);
    final cartCount =
        ref.watch(cartProvider).items.fold<int>(0, (sum, e) => sum + e.qty);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: menuAsync.when(
          data: (menu) => _HomeBody(
            menu: menu,
            cartCount: cartCount,
            t: t,
            discountAds: discountAds,
            selectedCategoryId: _selectedCategoryId ??
                (menu.categories.isNotEmpty ? menu.categories.first.id : null),
            onSelectCategory: (id) => setState(() => _selectedCategoryId = id),
            onRefresh: () async {
              _refreshRemoteHomeData();
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(t.t('generic_error'))),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _CartFab(count: cartCount),
      bottomNavigationBar: _BottomNav(current: 0),
    );
  }
}

class _HomeBody extends StatelessWidget {
  final MenuResponse menu;
  final int cartCount;
  final SushiLocalizations t;
  final List<AdminAdItem> discountAds;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelectCategory;
  final Future<void> Function() onRefresh;
  const _HomeBody({
    required this.menu,
    required this.cartCount,
    required this.t,
    required this.discountAds,
    required this.selectedCategoryId,
    required this.onSelectCategory,
    required this.onRefresh,
  });

  static const _text = Color(0xFF1B100D);

  @override
  Widget build(BuildContext context) {
    final categories = menu.categories;
    final selectedCategory = selectedCategoryId == null
        ? null
        : categories
            .where((c) => c.id == selectedCategoryId)
            .cast<CategoryModel?>()
            .firstWhere((c) => c != null, orElse: () => null);
    final selectedCategoryTitle = selectedCategory == null
        ? t.t('popular_now')
        : localizeCategoryName(selectedCategory.name, t);
    final filteredProducts = selectedCategory?.products ??
        categories.expand((c) => c.products).toList();
    final allProducts = filteredProducts;
    final popular = allProducts;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(),
                  const SizedBox(height: 12),
                  _LocationBar(label: t.t('deliver_to')),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _CategoryHeaderDelegate(
              height: 56,
              child: _CategoryChips(
                categories: categories,
                t: t,
                selectedId: selectedCategoryId,
                onSelect: onSelectCategory,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (discountAds.isNotEmpty) ...[
                    _DiscountCarousel(
                      ads: discountAds,
                      onTapBanner: (banner) =>
                          _handleBannerTap(context, banner),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(selectedCategoryTitle,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _text)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _PopularCard(product: popular[index]),
                childCount: popular.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBannerTap(
      BuildContext context, AdminAdItem banner) async {
    final action = banner.actionType.trim().toLowerCase();
    if (action == 'open_product') {
      final productId = banner.productId;
      if (productId != null && productId > 0) {
        context.push('/product?id=$productId');
      }
      return;
    }
    if (action == 'open_products') {
      if (banner.productIds.isEmpty) return;
      final ids = banner.productIds.join(',');
      final encodedTitle = Uri.encodeComponent(banner.title.trim());
      final suffix = encodedTitle.isNotEmpty ? '&title=$encodedTitle' : '';
      context.push('/products?ids=$ids$suffix');
      return;
    }
    if (action == 'open_category') {
      final categoryId = banner.categoryId;
      if (categoryId != null && categoryId > 0) {
        context.push('/category?id=$categoryId');
      }
      return;
    }
    if (action == 'open_discounts') {
      context.push('/discounts');
      return;
    }
    if (action == 'open_url') {
      final raw = (banner.targetUrl ?? '').trim();
      if (raw.isEmpty) return;
      if (raw.startsWith('/')) {
        context.push(raw);
        return;
      }
      Uri? uri = Uri.tryParse(raw);
      if (uri == null) return;
      if (!uri.hasScheme) {
        uri = Uri.tryParse('https://$raw');
      }
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  }
}

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  const _CategoryHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF8F6F6),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _CategoryHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _TopBar extends ConsumerWidget {
  static const _logoPath = 'assets/images/sushi-xl logo.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mailingState = ref.watch(mailingProvider);
    final localUnread = mailingState.hasUnread;
    final hiddenIds = mailingState.hiddenIds;
    final backendUnread = ref.watch(backendMailingsProvider).maybeWhen(
          data: (rows) {
            final visibleRows =
                rows.where((row) => !hiddenIds.contains(row.id)).toList();
            if (visibleRows.isEmpty) return false;
            final lastSeenId = mailingState.lastSeenId;
            if (lastSeenId == null) return true;
            final newestVisible = visibleRows.reduce(
              (left, right) =>
                  left.createdAt.isAfter(right.createdAt) ? left : right,
            );
            return newestVisible.id != lastSeenId;
          },
          orElse: () => false,
        );
    final hasUnread = localUnread || backendUnread;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 3))
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              _logoPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text('Sushi‑XL',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const Spacer(),
        _IconBubble(icon: Icons.search, onTap: () => context.push('/search')),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _IconBubble(
                icon: Icons.notifications_none,
                onTap: () => context.push('/mailings')),
            if (hasUnread)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: Color(0xFFEE482B), shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LocationBar extends ConsumerWidget {
  final String label;
  const _LocationBar({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final loc = ref.watch(deliveryLocationProvider);
    final address = (loc?.address.trim().isNotEmpty ?? false)
        ? _compactAddress(loc!.address)
        : t.t('location_not_set');
    return InkWell(
      onTap: () => context.push('/location'),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 16, color: Color(0xFFEE482B)),
          const SizedBox(width: 6),
          Text(
            t.t('deliver_to_your_address'),
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9A9A9A),
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Expanded(
              child: Text(address,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _compactAddress(String raw) {
    final parts =
        raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return raw;
    final filtered = parts.where((p) => !_isGenericAddressPart(p)).toList();
    if (filtered.isEmpty) return parts.last;

    final numbered = filtered.where(_hasHouseNumber).toList();
    if (numbered.isNotEmpty) {
      final house = numbered.last;
      final houseIndex = filtered.lastIndexOf(house);
      if (houseIndex > 0) {
        final street = filtered[houseIndex - 1];
        if (!_hasHouseNumber(street) &&
            street.toLowerCase() != house.toLowerCase()) {
          return '$street, $house';
        }
      }
      return house;
    }

    return filtered.last;
  }

  bool _hasHouseNumber(String value) {
    final lower = value.toLowerCase();
    return RegExp(r'\d').hasMatch(value) ||
        lower.contains('uy') ||
        lower.contains('dom') ||
        lower.contains('дом') ||
        lower.contains('house') ||
        lower.contains('kv') ||
        lower.contains('кв');
  }

  bool _isGenericAddressPart(String value) {
    final lower = value.toLowerCase();
    if (lower.isEmpty) return true;
    if (RegExp(r'^\d{5,6}$').hasMatch(lower)) return true;
    return lower.contains('o‘zbekiston') ||
        lower.contains('uzbekistan') ||
        lower.contains('узбекистан') ||
        lower.contains('ўзбекистон') ||
        lower.contains('toshkent') ||
        lower.contains('tashkent') ||
        lower.contains('ташкент') ||
        lower.contains('shahar') ||
        lower.contains('city') ||
        lower.contains('tuman') ||
        lower.contains('район') ||
        lower.contains('область') ||
        lower.contains('district') ||
        lower.contains('махалл') ||
        lower.contains('mahall') ||
        lower.contains('сход граждан') ||
        lower.contains('мфй');
  }
}

class _CategoryChips extends StatelessWidget {
  final List<CategoryModel> categories;
  final SushiLocalizations t;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  const _CategoryChips({
    required this.categories,
    required this.t,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final selected = cat.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(cat.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEE482B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected
                    ? [
                        const BoxShadow(
                            color: Color(0x33EE482B),
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ]
                    : [
                        const BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 6,
                            offset: Offset(0, 3))
                      ],
              ),
              child: Row(
                children: [
                  Icon(Icons.ramen_dining,
                      size: 16,
                      color: selected ? Colors.white : const Color(0xFF1B100D)),
                  const SizedBox(width: 6),
                  Text(
                    localizeCategoryName(cat.name, t),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF1B100D),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiscountCarousel extends StatefulWidget {
  final List<AdminAdItem> ads;
  final ValueChanged<AdminAdItem>? onTapBanner;
  const _DiscountCarousel({required this.ads, this.onTapBanner});

  @override
  State<_DiscountCarousel> createState() => _DiscountCarouselState();
}

class _DiscountCarouselState extends State<_DiscountCarousel> {
  late final PageController _controller;
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || widget.ads.isEmpty) return;
      _index = (_index + 1) % widget.ads.length;
      _controller.animateToPage(
        _index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.ads.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final ad = widget.ads[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () => widget.onTapBanner?.call(ad),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildImage(ad.image),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x14000000),
                                Color(0x77000000),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ad.title.trim().isEmpty
                                    ? 'Sushi-XL'
                                    : ad.title.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 10,
                                      color: Color(0x80000000),
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              if (ad.subtitle.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  ad.subtitle.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 8,
                                        color: Color(0x66000000),
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.ads.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _index == i ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _index == i
                    ? const Color(0xFFEE482B)
                    : const Color(0xFFD7D7D7),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(String path) {
    final p = path.trim();
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return Image.network(
        p,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    if (p.startsWith('assets/')) {
      return Image.asset(
        p,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    return _imageFallback();
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFEFEFEF),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined,
          color: Color(0xFFB0B0B0)),
    );
  }
}

class _PopularCard extends ConsumerWidget {
  final ProductModel product;
  const _PopularCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final image = product.imageUrl;
    final favorites = ref.watch(favoritesProvider);
    final isSaved = favorites.contains(product.id);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: image == null || image.isEmpty
                        ? null
                        : DecorationImage(
                            image: NetworkImage(image), fit: BoxFit.cover),
                    color: Colors.black12,
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(product.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('8 ${t.t('pieces_label')}',
                style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 11)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Text(
                  formatUzs(product.price),
                  style: const TextStyle(
                      color: Color(0xFFEE482B), fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => ref.read(cartProvider.notifier).add(product),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEE482B),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
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

class _CartFab extends StatelessWidget {
  final int count;
  const _CartFab({required this.count});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: const Color(0xFFEE482B),
      foregroundColor: Colors.white,
      onPressed: () => context.push('/cart'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.shopping_cart),
          if (count > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: const BoxDecoration(
                    color: Colors.black, shape: BoxShape.circle),
                child: Text('$count',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
        ],
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
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
                icon: Icons.home,
                label: t.t('home'),
                active: current == 0,
                onTap: () => context.go('/home')),
            _NavItem(
                icon: Icons.favorite_border,
                label: t.t('saved'),
                active: current == 1,
                onTap: () => context.push('/saved')),
            const SizedBox(width: 40),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBubble({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, size: 20),
      ),
    );
  }
}
