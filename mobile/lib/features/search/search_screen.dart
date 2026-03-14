import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../../core/format/currency.dart';
import '../../data/models/menu_models.dart';
import '../../core/localization/sushi_localizations.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final menuAsync = ref.watch(menuProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F6),
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => context.pop()),
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t.t('search_products_hint'),
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
      ),
      body: menuAsync.when(
        data: (menu) {
          final items = _filter(menu.categories, _query);
          if (items.isEmpty) {
            return Center(child: Text(t.t('no_results')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _SearchCard(product: items[index], cart: cart),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(t.t('generic_error'))),
      ),
    );
  }

  List<ProductModel> _filter(List<CategoryModel> categories, String query) {
    final all = categories.expand((c) => c.products).toList();
    if (query.isEmpty) return all;
    final q = query.toLowerCase();
    return all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }
}

class _SearchCard extends ConsumerWidget {
  final ProductModel product;
  final CartState cart;
  const _SearchCard({required this.product, required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = product.imageUrl;
    final qty = _qtyForProduct(cart, product.id);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
                Text(product.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(formatUzs(product.price),
                    style: const TextStyle(
                        color: Color(0xFFEE482B), fontWeight: FontWeight.w700)),
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
                ref
                    .read(cartProvider.notifier)
                    .updateQty(product, qty - 1, modifiers: const []);
              }
            },
            onPlus: () {
              if (qty == 0) {
                ref
                    .read(cartProvider.notifier)
                    .add(product, modifiers: const []);
              } else {
                ref
                    .read(cartProvider.notifier)
                    .updateQty(product, qty + 1, modifiers: const []);
              }
            },
          ),
        ],
      ),
    );
  }

  int _qtyForProduct(CartState cart, int productId) {
    int total = 0;
    for (final item in cart.items) {
      if (item.product.id == productId && item.modifiers.isEmpty) {
        total += item.qty;
      }
    }
    return total;
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
