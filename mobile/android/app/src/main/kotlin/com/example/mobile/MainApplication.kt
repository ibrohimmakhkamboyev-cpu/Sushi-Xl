package com.example.mobile

import android.app.Application
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
  override fun onCreate() {
    super.onCreate()
    val apiKey = getString(R.string.yandex_maps_api_key).trim()
    if (apiKey.isNotEmpty()) {
      MapKitFactory.setApiKey(apiKey)
    }
  }
}
