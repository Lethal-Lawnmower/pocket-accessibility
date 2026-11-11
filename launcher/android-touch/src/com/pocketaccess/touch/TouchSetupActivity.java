package com.pocketaccess.touch;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
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
 * Pocket Accessibility Touch's only screen: says whether the touch service is on, opens
 * the Android settings that switch it on, explains what it does and the Restricted
 * setting step, and opens the game app.  The gestures themselves are explained in the
 * game app's Touch controls page.  Plain text and standard buttons only, so every control
 * works with TalkBack's double tap.
 */
public final class TouchSetupActivity extends Activity {
    private static final String[] GAME_APPS = { "com.pocketaccessibility.app", "com.pocketaccess.androidtest" };
    private TextView state;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        setTitle("Pocket Accessibility Touch");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = (int) (16 * getResources().getDisplayMetrics().density);
        root.setPadding(margin, margin, margin, margin);

        state = new TextView(this);
        state.setTextAppearance(android.R.style.TextAppearance_Medium);
        state.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        root.addView(state);

        button(root, "Open accessibility settings", view -> openServiceSettings());
        button(root, "Open Pocket Accessibility", view -> openGame());

        heading(root, "What it does");
        text(root, "TalkBack normally takes every touch for itself, so a game cannot get swipes and taps. "
            + "This app's touch service hands the Pocket Accessibility game screen's touches straight to the game, "
            + "while TalkBack stays on and handles everything else: the launcher, the keyboard, notifications, "
            + "calls, system pop-ups and other apps. It is like direct touch on an iPhone.");
        text(root, "It only works together with TalkBack, and only while the game's screen is in front. "
            + "As soon as anything else comes up over the game, TalkBack gets the whole screen back. "
            + "The status bar and navigation buttons stay with TalkBack too. "
            + "It only decides who gets your touches; the game decides what each gesture does. "
            + "The gestures are listed in Pocket Accessibility, under Touch controls in its menu.");
        text(root, "Why it asks for accessibility access: Android only lets an accessibility service pass touches "
            + "through TalkBack. To know when the game is in front, it reads only the layout of the windows on screen: "
            + "which window is in front, what kind it is, and its size. It does not read what is on screen, "
            + "does not record anything, and never uses the internet; this app has no internet permission at all. "
            + "Android will warn that the service can see and control the screen, because it warns that for every "
            + "accessibility service. The code is open source, in the Pocket Accessibility repository on GitHub.");
        text(root, "Why it is a separate app: Google Play Protect blocks apps from outside the Play Store that include "
            + "an accessibility service, sometimes with no way to install them. Keeping the service here means "
            + "Pocket Accessibility itself always installs; only this optional app may be blocked on some phones.");
        text(root, "To switch it off, open the same settings and turn Pocket Accessibility touch off. "
            + "TalkBack then takes every touch again, the game screen included.");

        heading(root, "If Android says Restricted setting");
        text(root, "Android blocks accessibility services in apps that were not installed from an app store, "
            + "until you allow it once. If switching the service on says Restricted setting, close that message, then: "
            + "open this app's App info with the button below, open More options (the menu at the top), "
            + "choose Allow restricted settings and confirm. Then come back here, open the accessibility settings "
            + "again and switch the service on. Allow restricted settings only appears after you have tried "
            + "to switch the service on once.");
        button(root, "Open App info for Pocket Accessibility Touch", view -> openAppInfo());

        text(root, "The idea comes from the NVGT Bridge project; this is Pocket Accessibility's own code.");

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
        if (TouchPassthroughService.isEnabled(this)) {
            state.setText("Pocket Accessibility touch is on.");
        } else {
            state.setText("Pocket Accessibility touch is off. Switch it on in Android's accessibility settings.");
        }
    }

    private void openServiceSettings() {
        // Android's action for one service's own page (ACCESSIBILITY_DETAILS_SETTINGS) is not in the public
        // SDK, so this opens the list.  The two extras are Settings' own hint to
        // scroll to and highlight one entry; a Settings app that ignores them still opens the list.
        String service = new ComponentName(this, TouchPassthroughService.class).flattenToString();
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

    private void openGame() {
        for (String app : GAME_APPS) {
            Intent launch = getPackageManager().getLaunchIntentForPackage(app);
            if (launch != null && tryStart(launch)) return;
        }
        state.setText("Pocket Accessibility is not installed. Get it from the Releases page of the "
            + "pocket-accessibility repository on GitHub.");
    }

    private void openAppInfo() {
        Intent info = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", getPackageName(), null));
        if (!tryStart(info)) state.setText("App info could not be opened. Open Settings, Apps, Pocket Accessibility Touch yourself.");
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

    private void button(LinearLayout root, String text, View.OnClickListener action) {
        Button button = new Button(this);
        button.setText(text);
        button.setOnClickListener(action);
        root.addView(button);
    }
}
