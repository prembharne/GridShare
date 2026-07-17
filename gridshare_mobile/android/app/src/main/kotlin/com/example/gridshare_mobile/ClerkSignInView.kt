package com.example.gridshare_mobile

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.foundation.layout.fillMaxSize
import com.clerk.api.Clerk
import com.clerk.api.session.Session
import com.clerk.api.user.User
import com.clerk.ui.auth.AuthMode
import com.clerk.ui.auth.AuthView
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ClerkSignInViewFactory(
    private val messenger: io.flutter.plugin.common.BinaryMessenger
) : PlatformViewFactory(io.flutter.plugin.common.StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ClerkSignInView(context, messenger, viewId)
    }
}

class ClerkSignInView(
    private val context: Context,
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
    private val viewId: Int
) : PlatformView {

    private val channel = MethodChannel(messenger, "gridshare_mobile/clerk_auth")
    private var composeView: ComposeView? = null
    private var isSignedIn = false

    init {
        setupView()
    }

    private fun setupView() {
        composeView = ComposeView(context).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )

            // Check if already signed in when view is attached
            addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {
                    checkAndNotifyIfSignedIn()
                }
                override fun onViewDetachedFromWindow(v: View) {}
            })

            setContent {
                AuthView(
                    modifier = androidx.compose.ui.Modifier.fillMaxSize(),
                    preferGoogleOneTap = true,
                    isDismissible = false,
                    mode = AuthMode.SignInOrUp,
                    onAuthComplete = {
                        // Authentication completed, get session token and user info
                        onAuthenticationComplete()
                    }
                )
            }
        }
    }

    private fun checkAndNotifyIfSignedIn() {
        // Check if there's already an active session
        val session = Clerk.session
        if (session != null && session.status == Session.SessionStatus.ACTIVE && !isSignedIn) {
            val user = Clerk.user
            if (user != null) {
                val token = session.lastActiveToken?.jwt
                if (token != null) {
                    isSignedIn = true
                    notifySignInComplete(token, user)
                }
            }
        }
    }

    private fun onAuthenticationComplete() {
        // Give Clerk a moment to update session state
        composeView?.postDelayed({
            checkAndNotifyIfSignedIn()
        }, 500)
    }

    private fun notifySignInComplete(accessToken: String, user: User) {
        val userId = user.id
        val userName = user.firstName?.let { fn ->
            user.lastName?.let { ln -> "$fn $ln" } ?: fn
        } ?: user.username ?: "User"
        val userPhone = user.phoneNumbers?.firstOrNull()?.phoneNumber ?: ""

        channel.invokeMethod("onSignInComplete", mapOf(
            "accessToken" to accessToken,
            "userId" to userId,
            "userName" to userName,
            "userPhone" to userPhone
        ))
    }

    override fun getView(): View? {
        return composeView
    }

    override fun dispose() {
        composeView?.disposeComposition()
        composeView = null
    }
}