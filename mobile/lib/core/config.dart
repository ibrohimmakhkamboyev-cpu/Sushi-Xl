const String yandexJsApiKey = String.fromEnvironment(
  'YANDEX_JS_API_KEY',
  defaultValue: '',
);
const String yandexGeocoderApiKey = String.fromEnvironment(
  'YANDEX_GEOCODER_API_KEY',
  defaultValue: yandexJsApiKey,
);
const String yandexMobileApiKey = String.fromEnvironment(
  'YANDEX_MOBILE_API_KEY',
  defaultValue: '',
);
const String geocoderProxyBaseUrl = String.fromEnvironment(
  'GEOCODER_PROXY_BASE_URL',
  defaultValue: '',
);
const String telegramBotToken = String.fromEnvironment(
  'TELEGRAM_BOT_TOKEN',
  defaultValue: '',
);
const String telegramGroupId = String.fromEnvironment(
  'TELEGRAM_GROUP_ID',
  defaultValue: '',
);

const bool useBackend = bool.fromEnvironment(
  'USE_BACKEND',
  defaultValue: true,
);

const bool usePosterMenu = bool.fromEnvironment(
  'USE_POSTER_MENU',
  defaultValue: false,
);

const String posterApiToken = String.fromEnvironment(
  'POSTER_API_TOKEN',
  defaultValue: '',
);

const String posterAccount = String.fromEnvironment(
  'POSTER_ACCOUNT',
  defaultValue: '',
);

const String posterBaseUrl = String.fromEnvironment(
  'POSTER_BASE_URL',
  defaultValue: 'https://joinposter.com',
);

const String posterProductsPath = String.fromEnvironment(
  'POSTER_PRODUCTS_PATH',
  defaultValue: '/api/menu.getProducts',
);

const String posterCategoriesPath = String.fromEnvironment(
  'POSTER_CATEGORIES_PATH',
  defaultValue: '/api/menu.getCategories',
);

const double restaurantLat = 41.2995; // Tashkent (default)
const double restaurantLng = 69.2401;
