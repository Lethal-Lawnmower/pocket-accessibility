package com.pocketaccess.launcher;

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
 * Touch controls: explains Pocket Accessibility touch (TouchPassthroughService), says
 * whether it is on, and opens the Android settings that switch it on.  Plain text and
 * standard buttons only, so every control works with TalkBack's double tap.
 */
public final class TouchControlsActivity extends Activity {
    private TextView state;
    private Button openSettings;

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

        openSettings = button(root, "Open accessibility settings for Pocket Accessibility touch", view -> openServiceSettings());

        heading(root, "What it does");
        text(root, "TalkBack normally takes every touch for itself, so a game cannot get swipes and taps. "
            + "Pocket Accessibility touch hands the game screen's touches straight to the game, "
            + "while TalkBack stays on and handles everything else: this launcher, the keyboard, notifications, "
            + "calls, system pop-ups and other apps. It is like direct touch on an iPhone.");
        text(root, "It only works together with TalkBack, and only while the game's screen is in front. "
            + "As soon as anything else comes up over the game, TalkBack gets the whole screen back. "
            + "The status bar and navigation buttons stay with TalkBack too. "
            + "It only decides who gets your touches; the game decides what each gesture does.");
        text(root, "Why it asks for accessibility access: Android only lets an accessibility service pass touches "
            + "through TalkBack. To know when the game is in front, it reads only the layout of the windows on screen: "
            + "which window is in front, what kind it is, and its size. It does not read what is on screen, "
            + "does not record anything, and never uses the internet. It is part of this app; "
            + "you do not need to install anything else. Android will warn that the service can see and control "
            + "the screen, because it warns that for every accessibility service.");
        text(root, "To switch it off, open the same settings and turn Pocket Accessibility touch off. "
            + "TalkBack then takes every touch again, the game screen included.");

        heading(root, "If Android says Restricted setting");
        text(root, "Android blocks accessibility services in apps that were not installed from an app store, "
            + "until you allow it once. If switching the service on says Restricted setting, close that message, then: "
            + "open this app's App info with the button below, open More options (the menu at the top), "
            + "choose Allow restricted settings and confirm. Then come back here, open the accessibility settings "
            + "again and switch the service on. Allow restricted settings only appears after you have tried "
            + "to switch the service on once.");
        button(root, "Open App info for Pocket Accessibility", view -> openAppInfo());

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
        if (Build.VERSION.SDK_INT < 30) {
            state.setText("Pocket Accessibility touch needs Android 11 or later. This device has an older Android, "
                + "so touch on the game screen goes to TalkBack.");
            openSettings.setEnabled(false);
        } else if (TouchPassthroughService.isEnabled(this)) {
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
