package com.pocketaccess.launcher;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.util.Log;

import org.love2d.android.GameActivity;

/**
 * Loads Prism when the process starts, whichever screen Android opens first, and keeps
 * track of the game's activity so the save editor can close it.
 *
 * Prism has to be loaded through Java at least once: only System.loadLibrary
 * runs its JNI_OnLoad, and the game's FFI load alone leaves Prism without a Java
 * VM, which crashes it (docs/access/android.md).
 */
public final class PocketApplication extends Application {
    private static Activity gameActivity;

    @Override
    public void onCreate() {
        super.onCreate();
        try {
            System.loadLibrary("prism");
        } catch (UnsatisfiedLinkError error) {
            // the game reports the same problem through its own speech setup and runs silent
            Log.e("PocketAccess", "Prism could not be loaded", error);
        }
        registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity activity, Bundle saved) {
                if (activity instanceof GameActivity) gameActivity = activity;
            }

            @Override
            public void onActivityDestroyed(Activity activity) {
                if (activity == gameActivity) gameActivity = null;
            }

            @Override
            public void onActivityStarted(Activity activity) {}

            @Override
            public void onActivityResumed(Activity activity) {}

            @Override
            public void onActivityPaused(Activity activity) {}

            @Override
            public void onActivityStopped(Activity activity) {}

            @Override
            public void onActivitySaveInstanceState(Activity activity, Bundle state) {}
        });
    }

    static void finishGameActivity() {
        if (gameActivity != null) gameActivity.finish();
    }
}
