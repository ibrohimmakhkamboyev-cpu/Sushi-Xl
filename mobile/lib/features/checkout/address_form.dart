import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/providers.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../data/models/address_models.dart';

class AddressForm extends ConsumerStatefulWidget {
  final int userId;
  const AddressForm({super.key, required this.userId});

  @override
  ConsumerState<AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<AddressForm> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());
      await ref.read(addressRepositoryProvider).createAddress(
            AddressIn(
              userId: widget.userId,
              label: _labelController.text.trim().isEmpty
                  ? null
                  : _labelController.text.trim(),
              addressLine: _addressController.text.trim(),
              lat: lat,
              lng: lng,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.t('add_address'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _labelController,
            decoration:
                InputDecoration(labelText: t.t('address_label_home_office')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(labelText: t.t('address')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _latController,
            decoration: InputDecoration(labelText: t.t('latitude_optional')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lngController,
            decoration: InputDecoration(labelText: t.t('longitude_optional')),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            child: Text(_loading ? '...' : t.t('save')),
          ),
        ],
      ),
    );
  }
}
