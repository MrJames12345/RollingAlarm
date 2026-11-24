package com.casellaweb.rolling_alarm

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native Google Play In-App Review bridge using `com.google.android.play:review`.
 *
 * Replaces the pub.dev `in_app_review` wrapper plugin (which unconditionally
 * applies legacy `kotlin-android` and fails to configure under AGP 9.0.1 with
 * `android.builtInKotlin=true`).
 */
class PlayReviewBridge(
    private val activityProvider: () -> Activity?,
    private val isForegroundUnlocked: () -> Boolean = { true },
) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var cachedManager: ReviewManager? = null
    private var cachedReviewInfo: ReviewInfo? = null
    private var cachedReviewAtElapsedMs: Long = 0L

    fun attach(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        clearCache()
    }

    private fun clearCache() {
        cachedManager = null
        cachedReviewInfo = null
        cachedReviewAtElapsedMs = 0L
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> isAvailable(result)
            "requestReview" -> requestReview(result)
            "openStoreListing" -> openStoreListing(result)
            else -> result.notImplemented()
        }
    }

    private fun activeActivity(): Activity? {
        val activity = activityProvider() ?: return null
        if (activity.isFinishing || activity.isDestroyed) return null
        return activity
    }

    /**
     * Play Core's `launchReviewFlow` silently drops prompts when the hosting
     * Activity is backgrounded (`moveTaskToBack`) or behind the lock screen.
     * Require a live, resumed, unlocked Activity before reporting available so
     * Dart does not burn the 120-day cooldown on a lock-screen dismissal.
     */
    private fun activeForegroundActivity(): Activity? {
        val activity = activeActivity() ?: return null
        if (!isForegroundUnlocked()) return null
        return activity
    }

    private fun safeSuccess(
        replied: AtomicBoolean,
        result: MethodChannel.Result,
        value: Any?,
    ) {
        if (channel == null || !replied.compareAndSet(false, true)) return
        try {
            result.success(value)
        } catch (_: Exception) {
        }
    }

    private fun safeError(
        replied: AtomicBoolean,
        result: MethodChannel.Result,
        code: String,
        message: String?,
    ) {
        if (channel == null || !replied.compareAndSet(false, true)) return
        try {
            result.error(code, message, null)
        } catch (_: Exception) {
        }
    }

    private fun isAvailable(result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        val activity = activeForegroundActivity()
        if (activity == null) {
            clearCache()
            safeSuccess(replied, result, false)
            return
        }
        try {
            val manager = ReviewManagerFactory.create(activity.applicationContext)
            manager.requestReviewFlow().addOnCompleteListener { task ->
                if (channel == null) return@addOnCompleteListener
                if (task.isSuccessful && activeForegroundActivity() != null) {
                    cachedManager = manager
                    cachedReviewInfo = task.result
                    cachedReviewAtElapsedMs = SystemClock.elapsedRealtime()
                    safeSuccess(replied, result, true)
                } else {
                    clearCache()
                    safeSuccess(replied, result, false)
                }
            }
        } catch (_: Exception) {
            clearCache()
            safeSuccess(replied, result, false)
        }
    }

    private fun requestReview(result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        val activity = activeForegroundActivity()
        if (activity == null) {
            clearCache()
            safeError(
                replied,
                result,
                "no_activity",
                "Foreground unlocked Android activity not available",
            )
            return
        }
        try {
            val nowElapsed = SystemClock.elapsedRealtime()
            val freshInfo = cachedReviewInfo?.takeIf {
                nowElapsed - cachedReviewAtElapsedMs < CACHE_TTL_MS
            }
            val pairedManager = if (freshInfo != null) cachedManager else null
            clearCache()

            if (freshInfo != null && pairedManager != null) {
                pairedManager.launchReviewFlow(activity, freshInfo)
                    .addOnCompleteListener {
                        safeSuccess(replied, result, null)
                    }
                return
            }

            val manager = ReviewManagerFactory.create(activity.applicationContext)
            manager.requestReviewFlow().addOnCompleteListener { task ->
                if (channel == null) return@addOnCompleteListener
                val liveActivity = activeForegroundActivity()
                if (liveActivity == null) {
                    safeError(
                        replied,
                        result,
                        "no_activity",
                        "Foreground unlocked Android activity no longer available",
                    )
                    return@addOnCompleteListener
                }
                if (task.isSuccessful) {
                    manager.launchReviewFlow(liveActivity, task.result)
                        .addOnCompleteListener {
                            safeSuccess(replied, result, null)
                        }
                } else {
                    safeError(
                        replied,
                        result,
                        "review_unavailable",
                        "Google Play In-App Review unavailable",
                    )
                }
            }
        } catch (e: Exception) {
            safeError(replied, result, "review_failed", e.message)
        }
    }

    private fun openStoreListing(result: MethodChannel.Result) {
        val activity = activeActivity()
        if (activity == null) {
            result.error("no_activity", "Android activity not available", null)
            return
        }
        val pkg = activity.packageName
        try {
            val marketIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=$pkg"),
            ).apply {
                setPackage(PLAY_STORE_PACKAGE)
            }
            activity.startActivity(marketIntent)
            result.success(null)
            return
        } catch (_: ActivityNotFoundException) {
            // Fall through to web Play Store URL when Play Store app is absent.
        } catch (_: Exception) {
            // Fall through to web Play Store URL on OEM intent restriction.
        }

        try {
            val webIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$pkg"),
            )
            activity.startActivity(webIntent)
            result.success(null)
        } catch (e: Exception) {
            result.error("store_open_failed", e.message, null)
        }
    }

    companion object {
        const val CHANNEL = "com.casellaweb.rolling_alarm/play_review"
        private const val PLAY_STORE_PACKAGE = "com.android.vending"
        private const val CACHE_TTL_MS = 30_000L
    }
}
