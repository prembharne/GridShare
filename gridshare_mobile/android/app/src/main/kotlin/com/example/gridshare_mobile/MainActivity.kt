package com.example.gridshare_mobile

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import com.example.gridshare_mobile.ClerkSignInViewFactory

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        // Register Clerk SignIn platform view
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "gridshare_mobile/clerk_signin",
            ClerkSignInViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
