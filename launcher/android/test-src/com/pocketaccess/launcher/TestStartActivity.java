package com.pocketaccess.launcher;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.system.ErrnoException;
import android.system.Os;
import android.util.Log;

import org.love2d.android.GameActivity;

/**
 * Test builds only (build_apk.py --test-hooks): starts the game with environment
 * variables from an intent, so a scripted run can name a driver, a ROM and a silent
 * start.  Never part of a build for players.
 *
 *   am start -n APP/com.pocketaccess.launcher.TestStartActivity --es env "A=1;;B=2"
 */
public final class TestStartActivity extends Activity {
    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        String variables = getIntent().getStringExtra("env");
        try {
            if (variables != null) {
                for (String pair : variables.split(";;")) {
                    int equals = pair.indexOf('=');
                    if (equals > 0) Os.setenv(pair.substring(0, equals), pair.substring(equals + 1), true);
                }
            }
            startActivity(new Intent(this, GameActivity.class));
        } catch (ErrnoException error) {
            Log.e("PocketAccess", "test start failed", error);
        }
        finish();
    }
}
