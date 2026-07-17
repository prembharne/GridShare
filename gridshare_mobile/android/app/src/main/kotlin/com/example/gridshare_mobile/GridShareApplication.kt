package com.example.gridshare_mobile

import android.app.Application
import com.clerk.api.Clerk

class GridShareApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // Initialize Clerk with the publishable key from manifest
        val publishableKey = BuildConfig.CLERK_PUBLISHABLE_KEY
        if (publishableKey.isNotEmpty()) {
            Clerk.initialize(this, publishableKey)
        }
    }
}