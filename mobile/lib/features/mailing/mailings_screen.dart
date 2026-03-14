import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../../core/localization/sushi_localizations.dart';

class MailingsScreen extends ConsumerStatefulWidget {
  const MailingsScreen({super.key});

  @override
  ConsumerState<MailingsScreen> createState() => _MailingsScreenState();
}

class _MailingsScreenState extends ConsumerState<MailingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.invalidate(backendMailingsProvider);
      List<MailingItem> backendRows = const <MailingItem>[];
      try {
        backendRows = await ref.read(backendMailingsProvider.future);
      } catch (_) {}
      if (!mounted) return;
      await ref
          .read(mailingProvider.notifier)
          .markAllSeen(externalItems: backendRows);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final state = ref.watch(mailingProvider);
    final backendMailings = ref.watch(backendMailingsProvider).maybeWhen(
          data: (rows) => rows,
          orElse: () => const <MailingItem>[],
        );
    final hiddenIds = state.hiddenIds;
    final mergedById = <int, MailingItem>{};
    for (final item in [
      ...backendMailings.where((e) => !hiddenIds.contains(e.id)),
      ...state.visibleItems,
    ]) {
      final current = mergedById[item.id];
      if (current == null || item.createdAt.isAfter(current.createdAt)) {
        mergedById[item.id] = item;
      }
    }
    final items = mergedById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F6F6),
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFEE482B)),
        ),
        title: Text(t.t('mailings'),
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: Color(0xFF1B100D))),
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                t.t('no_mailings_yet'),
                style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 16),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return _MailingCard(
                  item: item,
                  onClose: () =>
                      ref.read(mailingProvider.notifier).remove(item.id),
                );
              },
            ),
    );
  }
}

class _MailingCard extends StatelessWidget {
  final MailingItem item;
  final VoidCallback onClose;
  const _MailingCard({required this.item, required this.onClose});

  @override
  Widget build(BuildContext context) {
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
          Stack(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: _preview(item.image),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 14, color: Color(0xFF333333)),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(item.title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (item.message.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                item.message,
                style: const TextStyle(
                  color: Color(0xFF4C4C4C),
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              item.createdAt.toLocal().toString().split('.').first,
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(String image) {
    if (image.isEmpty) {
      return Container(
        color: const Color(0xFFFFE5D9),
        alignment: Alignment.center,
        child: const Icon(
          Icons.notifications_active_rounded,
          size: 42,
          color: Color(0xFFEE482B),
        ),
      );
    }
    if (image.startsWith('http')) {
      return Image.network(image, fit: BoxFit.cover);
    }
    if (image.startsWith('assets/')) {
      return Image.asset(image, fit: BoxFit.cover);
    }
    return Image.file(File(image), fit: BoxFit.cover);
  }
}
