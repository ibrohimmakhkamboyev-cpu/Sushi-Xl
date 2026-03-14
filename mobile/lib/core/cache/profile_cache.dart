import 'package:shared_preferences/shared_preferences.dart';

class ProfileCache {
  static const _photoKey = 'profile_photo_path_v1';

  Future<void> savePhotoPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_photoKey);
    } else {
      await prefs.setString(_photoKey, path);
    }
  }

  Future<String?> loadPhotoPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_photoKey);
  }
}
