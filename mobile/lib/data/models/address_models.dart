class AddressModel {
  final int id;
  final int userId;
  final String? label;
  final String addressLine;
  final double? lat;
  final double? lng;

  AddressModel({
    required this.id,
    required this.userId,
    this.label,
    required this.addressLine,
    this.lat,
    this.lng,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      label: json['label'] as String?,
      addressLine: json['address_line'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }
}

class AddressIn {
  final int userId;
  final String? label;
  final String addressLine;
  final double? lat;
  final double? lng;

  AddressIn({
    required this.userId,
    this.label,
    required this.addressLine,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'label': label,
        'address_line': addressLine,
        'lat': lat,
        'lng': lng,
      };
}
