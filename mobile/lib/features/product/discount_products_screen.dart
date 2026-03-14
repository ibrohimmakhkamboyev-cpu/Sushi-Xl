import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/currency.dart';
import '../../core/state/catalog_providers.dart';
import '../../core/state/providers.dart';
import '../../data/models/menu_models.dart';

class DiscountProductsPage extends ConsumerWidget {
  const DiscountProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discountedAsync = ref.watch(discountedProductsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F6),
      appBar: AppBar(
        title: const Text('Discount Products'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: discountedAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No discounted products yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _DiscountListCard(product: products[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load discounts: $err')),
      ),
    );
  }
}

class _DiscountListCard extends ConsumerWidget {
  final ProductModel product;

  const _DiscountListCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = product.imageUrl;
    return InkWell(
      onTap: () => context.push('/product?id=${product.id}'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFFF0F0F0),
                image: image == null || image.isEmpty
                    ? null
                    : DecorationImage(
                        image: NetworkImage(image),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.discountPercent != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFECE8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '-${product.discountPercent}% ',
                        style: const TextStyle(
                          color: Color(0xFFEE482B),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((product.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7C7C7C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        formatUzs(product.price),
                        style: const TextStyle(
                          color: Color(0xFFEE482B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (product.isDiscounted) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatUzs(product.oldPrice),
                          style: const TextStyle(
                            color: Color(0xFF9A9A9A),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => ref.read(cartProvider.notifier).add(product),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEE482B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
