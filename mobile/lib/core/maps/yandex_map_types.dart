class YandexMapMarker {
  final double lat;
  final double lng;
  final String title;
  final String subtitle;

  const YandexMapMarker(
    this.lat,
    this.lng, {
    this.title = '',
    this.subtitle = '',
  });
}
