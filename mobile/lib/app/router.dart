import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/home/home_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/profile_edit_screen.dart';
import '../features/product/product_screen.dart';
import '../features/product/product_list_screen.dart';
import '../features/product/discount_products_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/tracking/tracking_screen.dart';
import '../features/checkout/address_form.dart';
import '../features/profile/order_history_screen.dart';
import '../features/support/support_screen.dart';
import '../features/support/support_chat_screen.dart';
import '../features/orders/order_success_screen.dart';
import '../features/saved/saved_screen.dart';
import '../features/search/search_screen.dart';
import '../features/location/location_picker_screen.dart';
import '../features/mailing/mailings_screen.dart';
import '../core/localization/sushi_localizations.dart';

GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/category',
        builder: (context, state) {
          final categoryId =
              int.tryParse(state.uri.queryParameters['id'] ?? '');
          return ProductListScreen(categoryId: categoryId);
        },
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) {
          final rawIds = (state.uri.queryParameters['ids'] ?? '').trim();
          final ids = rawIds
              .split(',')
              .map((item) => int.tryParse(item.trim()))
              .whereType<int>()
              .where((id) => id > 0)
              .toList();
          final title = (state.uri.queryParameters['title'] ?? '').trim();
          return ProductListScreen(
            productIds: ids,
            titleOverride: title.isEmpty ? null : title,
          );
        },
      ),
      GoRoute(
        path: '/discounts',
        builder: (_, __) => const DiscountProductsPage(),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
          path: '/profile-edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(
        path: '/product',
        builder: (context, state) {
          final productId = int.tryParse(state.uri.queryParameters['id'] ?? '');
          return ProductScreen(productId: productId);
        },
      ),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
        path: '/order-success',
        builder: (context, state) {
          final orderId =
              int.tryParse(state.uri.queryParameters['orderId'] ?? '');
          return OrderSuccessScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/tracking',
        builder: (context, state) {
          final orderId =
              int.tryParse(state.uri.queryParameters['orderId'] ?? '');
          return TrackingScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/address',
        builder: (context, state) {
          final userId =
              int.tryParse(state.uri.queryParameters['userId'] ?? '');
          return AddressForm(userId: userId ?? 0);
        },
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) {
          final initialTab = state.uri.queryParameters['tab'] == 'past'
              ? OrderHistoryTab.past
              : OrderHistoryTab.active;
          return OrderHistoryScreen(initialTab: initialTab);
        },
      ),
      GoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
      GoRoute(
        path: '/support/chat',
        builder: (_, state) => SupportChatScreen(
          cancellationOrderId:
              int.tryParse(state.uri.queryParameters['cancelOrderId'] ?? ''),
        ),
      ),
      GoRoute(path: '/saved', builder: (_, __) => const SavedScreen()),
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(
          path: '/location', builder: (_, __) => const LocationPickerScreen()),
      GoRoute(path: '/mailings', builder: (_, __) => const MailingsScreen()),
    ],
    errorBuilder: (context, __) => Scaffold(
        body:
            Center(child: Text(SushiLocalizations.of(context).t('not_found')))),
  );
}
