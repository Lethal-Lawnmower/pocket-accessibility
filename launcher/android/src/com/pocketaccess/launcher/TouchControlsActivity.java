package com.pocketaccess.launcher;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Touch controls: the gestures, and whether Pocket Accessibility Touch is installed and on.
 * The touch service that hands the game screen's touches past TalkBack lives in that
 * separate, optional app (launcher/android-touch, decision 73), because Google Play Protect
 * blocks a sideloaded app that declares an accessibility service; this page only links to
 * it.  Plain text and standard buttons only, so every control works with TalkBack's double tap.
 */
public final class TouchControlsActivity extends Activity {
    /** Pocket Accessibility Touch: the release and its test build (build_touch_apk.py). */
    private static final String[] COMPANIONS = { "com.pocketaccessibility.touch", "com.pocketaccess.touchtest" };
    private static final String SERVICE_CLASS = "com.pocketaccess.touch.TouchPassthroughService";
    private static final String RELEASES = "https://github.com/Lethal-Lawnmower/pocket-accessibility/releases/latest";
    private TextView state;
    private Button action;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        setTitle("Touch controls");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(margin, margin, margin, margin);

        state = new TextView(this);
        state.setTextAppearance(android.R.style.TextAppearance_Medium);
        state.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        root.addView(state);

        action = button(root, "", view -> act());

        heading(root, "Pocket Accessibility Touch");
        text(root, "TalkBack normally takes every touch for itself, so a game cannot get swipes and taps. "
            + "Pocket Accessibility Touch is a small, optional companion app with one accessibility service: "
            + "while the game's screen is in front, it hands those touches straight to the game, and TalkBack "
            + "stays on and handles everything else. It is like direct touch on an iPhone.");
        text(root, "It is a separate download, from the same Releases page as this app, because Google Play Protect "
            + "blocks apps from outside the Play Store that include an accessibility service, sometimes with no way "
            + "to install them. Keeping it separate means this app always installs; if Play Protect blocks the "
            + "companion on your phone, you can still play with a controller.");
        text(root, "It does not read what is on screen, does not record anything, and has no internet permission. "
            + "Android warns that any accessibility service can see and control the screen. The code is open source, "
            + "in the Pocket Accessibility repository on GitHub. Its own screen explains how to switch it on.");

        // The gestures, as in README.md "Controls" and docs/access/android.md: keep the three in step.
        heading(root, "Gestures in the game");
        text(root, "They work anywhere on the game screen, held either way up. "
            + "What matters is how many fingers you use, not where you touch.");
        text(root, "Swipe: walk on the map. In menus, battles and dialogue, it moves the cursor.");
        text(root, "Two-finger swipe left or right: the previous or next thing on the map. "
            + "Two-finger swipe up or down: change the category. "
            + "Your two fingers can sit side by side or one above the other.");
        text(root, "Tap: spoken directions to what you picked, which keep coming as you walk. Tap again to stop them. "
            + "In Auto walking, a tap walks you there instead, and another tap stops.");
        text(root, "Double tap: A. Two-finger double tap: B. "
            + "Three-finger double tap: Start. Three-finger tap: Select.");
        text(root, "Two-finger triple tap on the title screen: back to this launcher. Save first; leaving does not save.");
        text(root, "Any gesture stops a walk.");
        text(root, "In the game's options, ACCESSIBILITY has TOUCH WALKING. Manual: each swipe is one step. "
            + "Hybrid: the game says the next straight stretch, like 18 up; swipe that way to walk all of it. "
            + "Auto: a tap walks all the way to what you picked, and another tap stops; swipes are single steps. "
            + "On a device that can vibrate, HAPTICS gives a light tick for each step and a firmer one "
            + "when you walk into something.");

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        // A wrapper, because fitting the system bars replaces a view's own padding.
        FrameLayout window = new FrameLayout(this);
        window.setFitsSystemWindows(true);
        window.addView(scroll);
        setContentView(window);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // the player may have just installed it, or switched it on or off
        String installed = installedCompanion();
        if (Build.VERSION.SDK_INT < 30) {
            state.setText("Touch on the game screen needs Android 11 or later. This device has an older Android, "
                + "so touch on the game screen goes to TalkBack. A controller works.");
            action.setText("Touch needs Android 11");
            action.setEnabled(false);
        } else if (installed == null) {
            state.setText("Pocket Accessibility Touch is not installed, so TalkBack keeps the game screen's touches.");
            action.setText("Get Pocket Accessibility Touch from the Releases page");
        } else if (serviceOn(installed)) {
            state.setText("Pocket Accessibility Touch is installed and on.");
            action.setText("Open Pocket Accessibility Touch");
        } else {
            state.setText("Pocket Accessibility Touch is installed but off. Open it to switch it on.");
            action.setText("Open Pocket Accessibility Touch");
        }
    }

    private void act() {
        String installed = installedCompanion();
        if (installed != null) {
            Intent launch = getPackageManager().getLaunchIntentForPackage(installed);
            if (launch != null && tryStart(launch)) return;
            state.setText("Pocket Accessibility Touch could not be opened. Open it from your apps.");
            return;
        }
        if (!tryStart(new Intent(Intent.ACTION_VIEW, Uri.parse(RELEASES)))) {
            state.setText("No browser could open the Releases page. It is on GitHub, in the pocket-accessibility repository.");
        }
    }

    /** The companion's package, or null when neither the release nor the test build is installed. */
    private String installedCompanion() {
        for (String name : COMPANIONS) {
            try {
                getPackageManager().getPackageInfo(name, 0);
                return name;
            } catch (PackageManager.NameNotFoundException absent) {
                // try the next
            }
        }
        return null;
    }

    /** Whether the companion's service is on: Settings lists every enabled service by component. */
    private boolean serviceOn(String companion) {
        String enabled = Settings.Secure.getString(getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null) return false;
        String ours = new ComponentName(companion, SERVICE_CLASS).flattenToString();
        String shortForm = new ComponentName(companion, SERVICE_CLASS).flattenToShortString();
        for (String entry : enabled.split(":")) {
            if (entry.equalsIgnoreCase(ours) || entry.equalsIgnoreCase(shortForm)) return true;
        }
        return false;
    }

    private boolean tryStart(Intent intent) {
        try {
            startActivity(intent);
            return true;
        } catch (ActivityNotFoundException | SecurityException error) {
            return false;
        }
    }

    private void heading(LinearLayout root, String text) {
        TextView view = text(root, text);
        view.setTextAppearance(android.R.style.TextAppearance_Medium);
        view.setPadding(0, view.getPaddingTop() + (int) (16 * getResources().getDisplayMetrics().density), 0, 0);
        if (Build.VERSION.SDK_INT >= 28) view.setAccessibilityHeading(true);
    }

    private TextView text(LinearLayout root, String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setPadding(0, (int) (8 * getResources().getDisplayMetrics().density), 0, 0);
        root.addView(view);
        return view;
    }

    private Button button(LinearLayout root, String text, View.OnClickListener action) {
        Button button = new Button(this);
        button.setText(text);
        button.setOnClickListener(action);
        root.addView(button);
        return button;
    }
}
