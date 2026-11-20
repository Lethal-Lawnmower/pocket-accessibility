package com.pocketaccess.launcher;

import android.accessibilityservice.AccessibilityServiceInfo;
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
import android.view.accessibility.AccessibilityManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Touch controls: the gestures, and the touch service that hands the game screen's touches
 * past TalkBack.  The service comes in one of the two Android downloads only (decision 74):
 * the standard APK has it built in; the no-touch APK leaves it out, for phones where Google
 * Play Protect blocks any sideloaded app with an accessibility service.  This page asks the
 * package manager which one this is.  Plain text and standard buttons only, so every control
 * works with TalkBack's double tap.
 */
public final class TouchControlsActivity extends Activity {
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

        heading(root, "The touch service");
        text(root, "TalkBack normally takes every touch for itself, so a game cannot get swipes and taps. "
            + "The touch service, Pocket Accessibility touch, hands the game screen's touches straight to the game, "
            + "while TalkBack stays on and handles everything else: this launcher, the keyboard, notifications, "
            + "calls, system pop-ups and other apps. It is like direct touch on an iPhone. It only works together "
            + "with TalkBack, and only while the game's screen is in front.");
        text(root, "Why it asks for accessibility access: Android only lets an accessibility service pass touches "
            + "through TalkBack. To know when the game is in front, it reads only the layout of the windows on screen. "
            + "It does not read what is on screen, does not record anything, and never uses the internet. Android "
            + "warns that any accessibility service can see and control the screen. The code is open source, in the "
            + "Pocket Accessibility repository on GitHub.");
        text(root, "There are two Android downloads. The standard one has the touch service built in. The no-touch "
            + "one leaves it out, because on some phones Google Play Protect blocks apps from outside the Play Store "
            + "that include an accessibility service, with no way to install them anyway. Both are the same app with "
            + "the same saves, so you can install one over the other.");

        heading(root, "If Android says Restricted setting");
        text(root, "Android blocks accessibility services in apps that were not installed from an app store, "
            + "until you allow it once. If switching the service on says Restricted setting, close that message, then: "
            + "open this app's App info with the button below, open More options (the menu at the top), "
            + "choose Allow restricted settings and confirm. Then come back here, open the accessibility settings "
            + "again and switch the service on. Allow restricted settings only appears after you have tried "
            + "to switch the service on once.");
        button(root, "Open App info for Pocket Accessibility", view -> openAppInfo());

        // The gestures, as in README.md "Controls" and docs/access/android.md: keep the three in step.
        heading(root, "Gestures in the game");
        text(root, "They work anywhere on the game screen, held either way up. "
            + "What matters is how many fingers you use, not where you touch.");
        text(root, "Swipe: walk on the map. In menus, battles and dialogue, it moves the cursor.");
        text(root, "Two-finger swipe left or right: the previous or next thing on the map. "
            + "Two-finger swipe up or down: change the category. "
            + "Your two fingers can sit side by side or one above the other.");
        text(root, "In battle, two-finger swipe up: your Pokémon's HP. Two-finger swipe down: the enemy's HP. "
            + "In a double battle you hear both on that side.");
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
        // the player may have just switched it on or off in Android's settings
        if (Build.VERSION.SDK_INT < 30) {
            state.setText("Touch on the game screen needs Android 11 or later. This device has an older Android, "
                + "so touch on the game screen goes to TalkBack. A controller works.");
            action.setText("Touch needs Android 11");
            action.setEnabled(false);
        } else if (!hasService()) {
            state.setText("This is the no-touch download: it has no touch service, so TalkBack keeps the game "
                + "screen's touches. A controller works. For touch gestures, install the standard download over it.");
            action.setText("Open the Releases page");
        } else if (serviceOn()) {
            state.setText("Pocket Accessibility touch is on.");
            action.setText("Open accessibility settings for Pocket Accessibility touch");
        } else {
            state.setText("Pocket Accessibility touch is off. Switch it on in Android's accessibility settings.");
            action.setText("Open accessibility settings for Pocket Accessibility touch");
        }
    }

    private void act() {
        if (hasService()) {
            openServiceSettings();
        } else if (!tryStart(new Intent(Intent.ACTION_VIEW, Uri.parse(RELEASES)))) {
            state.setText("No browser could open the Releases page. It is on GitHub, in the pocket-accessibility repository.");
        }
    }

    /** Whether this download has the touch service (the standard APK) or not (the no-touch APK). */
    private boolean hasService() {
        try {
            getPackageManager().getServiceInfo(new ComponentName(this, SERVICE_CLASS), 0);
            return true;
        } catch (PackageManager.NameNotFoundException absent) {
            return false;
        }
    }

    /** Whether the service is on, as Android's accessibility manager lists the enabled services.
     *  (Settings.Secure's enabled_accessibility_services read "off" on the emulator while the
     *  service was bound, 2026-11-10.) */
    private boolean serviceOn() {
        AccessibilityManager manager = getSystemService(AccessibilityManager.class);
        if (manager == null) return false;
        ComponentName ours = new ComponentName(this, SERVICE_CLASS);
        for (AccessibilityServiceInfo info
                : manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)) {
            if (info.getResolveInfo() == null || info.getResolveInfo().serviceInfo == null) continue;
            ComponentName name = new ComponentName(info.getResolveInfo().serviceInfo.packageName,
                info.getResolveInfo().serviceInfo.name);
            if (name.equals(ours)) return true;
        }
        return false;
    }

    private void openServiceSettings() {
        // Android's action for one service's own page (ACCESSIBILITY_DETAILS_SETTINGS) is not in the public
        // SDK, so this opens the list.  The two extras are Settings' own hint to
        // scroll to and highlight one entry; a Settings app that ignores them still opens the list.
        String service = new ComponentName(this, SERVICE_CLASS).flattenToString();
        Bundle highlight = new Bundle();
        highlight.putString(":settings:fragment_args_key", service);
        Intent list = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            .putExtra(":settings:fragment_args_key", service)
            .putExtra(":settings:show_fragment_args", highlight);
        if (!tryStart(list)) {
            state.setText("Android's accessibility settings could not be opened. Open Settings, Accessibility yourself.");
            return;
        }
        state.setText("In the list, choose Pocket Accessibility touch, which may be under Downloaded apps.");
    }

    private void openAppInfo() {
        Intent info = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", getPackageName(), null));
        if (!tryStart(info)) state.setText("App info could not be opened. Open Settings, Apps, Pocket Accessibility yourself.");
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
