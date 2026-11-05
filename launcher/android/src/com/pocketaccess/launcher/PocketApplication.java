package com.pocketaccess.launcher;

import android.app.Application;
import android.util.Log;

/**
 * Loads Prism when the process starts, whichever screen Android opens first.
 *
 * Prism has to be loaded through Java at least once: only System.loadLibrary
 * runs its JNI_OnLoad, and the game's FFI load alone leaves Prism without a Java
 * VM, which crashes it (docs/access/android.md).
 */
public final class PocketApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        try {
            System.loadLibrary("prism");
        } catch (UnsatisfiedLinkError error) {
            // the game reports the same problem through its own speech setup and runs silent
            Log.e("PocketAccess", "Prism could not be loaded", error);
        }
    }
}
