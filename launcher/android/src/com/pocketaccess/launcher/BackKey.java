package com.pocketaccess.launcher;

import android.app.Activity;
import android.os.Build;
import android.window.OnBackInvokedDispatcher;

/**
 * Routes Back to a screen's own close.  From Android 16, an app targeting API 36 gets
 * predictive Back: onBackPressed is no longer called and the activity simply finishes,
 * which left the game's blank activity (the backend) in front.  A registered callback
 * is still called, so screens with a backend behind them register one; onBackPressed
 * covers older Android.
 */
final class BackKey {
    private BackKey() {}

    static void route(Activity activity, Runnable onBack) {
        if (Build.VERSION.SDK_INT >= 33) {
            activity.getOnBackInvokedDispatcher()
                .registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, onBack::run);
        }
    }
}
