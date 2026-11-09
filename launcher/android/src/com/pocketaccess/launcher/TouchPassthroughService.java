package com.pocketaccess.launcher;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.KeyguardManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Rect;
import android.graphics.Region;
import android.os.Build;
import android.os.PowerManager;
import android.util.SparseArray;
import android.view.Display;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityWindowInfo;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * "Pocket Accessibility touch": while the game's screen is in front, its touches go
 * straight to the game, and TalkBack keeps handling everything else (Android's nearest
 * thing to iOS direct interaction; decision 66, docs/access/android.md "Touch service").
 *
 * Android only lets an accessibility service do this, through
 * setTouchExplorationPassthroughRegion (API 30): touches inside the region skip touch
 * exploration and reach the app as ordinary touches.  The region only counts while
 * this service itself requests touch exploration, which it does only while another
 * enabled service (TalkBack) does too, so a player without a screen reader is never
 * put into touch exploration by this service alone.
 *
 * What it reads: window types, bounds, layers and focus, and the class name of our own
 * package's window-state events, to know which window is the game's.  It reads no
 * screen text, keeps nothing, and never connects to anything.  The NVGT Bridge project
 * showed this approach works with TalkBack; this is our own code.
 *
 * Fail-safe rule: when anything is unknown, the region is empty, so TalkBack has the
 * whole screen.
 */
public final class TouchPassthroughService extends AccessibilityService {
    /** upstream love-android's game activity: the only window touches are handed to */
    static final String GAME_ACTIVITY = "org.love2d.android.GameActivity";
    private static final String OUR_ACTIVITIES = "com.pocketaccess.launcher.";

    /** Windows of our package known to be the game's (true) or a launcher screen (false). */
    private final Map<Integer, Boolean> ourWindows = new HashMap<>();
    /** The region last set per display, so unchanged regions are not set again. */
    private final Map<Integer, Region> applied = new HashMap<>();
    private boolean requestingTouchExploration;
    private AccessibilityManager accessibility;
    private AccessibilityManager.AccessibilityServicesStateChangeListener servicesListener;

    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            update();
        }
    };

    /** Whether this service is switched on in Android's accessibility settings. */
    static boolean isEnabled(Context context) {
        AccessibilityManager manager = context.getSystemService(AccessibilityManager.class);
        if (manager == null) return false;
        ComponentName ours = new ComponentName(context, TouchPassthroughService.class);
        for (AccessibilityServiceInfo info
                : manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)) {
            if (info.getResolveInfo() == null || info.getResolveInfo().serviceInfo == null) continue;
            ComponentName name = new ComponentName(info.getResolveInfo().serviceInfo.packageName,
                info.getResolveInfo().serviceInfo.name);
            if (name.equals(ours)) return true;
        }
        return false;
    }

    @Override
    protected void onServiceConnected() {
        accessibility = getSystemService(AccessibilityManager.class);
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_SCREEN_OFF);
        filter.addAction(Intent.ACTION_SCREEN_ON);
        filter.addAction(Intent.ACTION_USER_PRESENT);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(screenReceiver, filter);
        }
        if (Build.VERSION.SDK_INT >= 33 && accessibility != null) {
            // TalkBack switched on or off while we run
            servicesListener = manager -> update();
            accessibility.addAccessibilityServicesStateChangeListener(servicesListener);
        }
        update();
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) noteWindow(event);
        update();
    }

    /**
     * Window ids cannot say which activity a window belongs to, but a window-state event
     * from an activity's window carries that activity's class name.  Only class names of
     * the game's activity and our launcher screens are trusted; others (dialogs, panes)
     * leave what is known unchanged.
     */
    private void noteWindow(AccessibilityEvent event) {
        if (event.getPackageName() == null || event.getClassName() == null) return;
        if (!getPackageName().contentEquals(event.getPackageName())) return;
        String name = event.getClassName().toString();
        if (name.equals(GAME_ACTIVITY)) ourWindows.put(event.getWindowId(), true);
        else if (name.startsWith(OUR_ACTIVITIES)) ourWindows.put(event.getWindowId(), false);
    }

    @Override
    public void onInterrupt() {
        // no feedback of our own to stop
    }

    @Override
    public void onDestroy() {
        try {
            unregisterReceiver(screenReceiver);
        } catch (IllegalArgumentException notRegistered) {
            // onServiceConnected never ran
        }
        if (servicesListener != null && accessibility != null && Build.VERSION.SDK_INT >= 33) {
            accessibility.removeAccessibilityServicesStateChangeListener(servicesListener);
        }
        for (int display : new HashSet<>(applied.keySet())) setRegion(display, new Region());
        super.onDestroy();
    }

    /** Recomputes everything; cheap enough to run on every window event. */
    private void update() {
        boolean screenReader = anotherServiceExploresByTouch();
        if (screenReader != requestingTouchExploration) setTouchExplorationRequest(screenReader);

        SparseArray<List<AccessibilityWindowInfo>> all = getWindowsOnAllDisplays();
        Set<Integer> present = new HashSet<>();
        Set<Integer> displays = new HashSet<>(applied.keySet());
        displays.add(Display.DEFAULT_DISPLAY);
        for (int i = 0; i < all.size(); i++) {
            displays.add(all.keyAt(i));
            for (AccessibilityWindowInfo window : all.valueAt(i)) present.add(window.getId());
        }
        ourWindows.keySet().retainAll(present);

        boolean usable = screenReader && screenIsOnAndUnlocked();
        for (int display : displays) {
            List<AccessibilityWindowInfo> windows = all.get(display);
            Region region = usable && windows != null ? gameRegion(windows) : new Region();
            setRegion(display, region);
        }
    }

    /**
     * The game window's bounds, less every system window drawn above it (status and
     * navigation bars, a heads-up notification), which stay with TalkBack.  Empty unless
     * the game window is the active, focused window, and empty while the keyboard, an
     * overlay or another app's window is shown above it.
     */
    private Region gameRegion(List<AccessibilityWindowInfo> windows) {
        AccessibilityWindowInfo game = null;
        for (AccessibilityWindowInfo window : windows) {
            if (window.getType() == AccessibilityWindowInfo.TYPE_APPLICATION
                && Boolean.TRUE.equals(ourWindows.get(window.getId()))) {
                game = window;
                break;
            }
        }
        if (game == null || !game.isFocused() || !game.isActive()) return new Region();

        Rect bounds = new Rect();
        game.getBoundsInScreen(bounds);
        Region region = new Region(bounds);
        Rect above = new Rect();
        for (AccessibilityWindowInfo window : windows) {
            if (window.getId() == game.getId()) continue;
            int type = window.getType();
            // The keyboard: anywhere on this display, the whole screen goes back to TalkBack.
            if (type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) return new Region();
            if (window.getLayer() <= game.getLayer()) continue;
            window.getBoundsInScreen(above);
            if (!Rect.intersects(above, bounds)) continue;
            if (type == AccessibilityWindowInfo.TYPE_SYSTEM
                || type == AccessibilityWindowInfo.TYPE_SPLIT_SCREEN_DIVIDER) {
                region.op(above, Region.Op.DIFFERENCE);
            } else {
                // another app, a dialog, an overlay (including other accessibility services'
                // and the magnifier's): not the game, so TalkBack gets the whole screen
                return new Region();
            }
        }
        return region;
    }

    private boolean screenIsOnAndUnlocked() {
        PowerManager power = getSystemService(PowerManager.class);
        KeyguardManager keyguard = getSystemService(KeyguardManager.class);
        if (power == null || !power.isInteractive()) return false;
        return keyguard == null || !keyguard.isKeyguardLocked();
    }

    /** True when another enabled service (TalkBack, normally) asks for touch exploration. */
    private boolean anotherServiceExploresByTouch() {
        if (accessibility == null) return false;
        ComponentName ours = new ComponentName(this, TouchPassthroughService.class);
        for (AccessibilityServiceInfo info
                : accessibility.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)) {
            if (info.getResolveInfo() != null && info.getResolveInfo().serviceInfo != null) {
                ComponentName name = new ComponentName(info.getResolveInfo().serviceInfo.packageName,
                    info.getResolveInfo().serviceInfo.name);
                if (name.equals(ours)) continue;
            }
            if ((info.flags & AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE) != 0) return true;
        }
        return false;
    }

    private void setTouchExplorationRequest(boolean request) {
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) return;
        if (request) info.flags |= AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE;
        else info.flags &= ~AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE;
        setServiceInfo(info);
        requestingTouchExploration = request;
        // a region set before the request may not have taken effect: set them all again
        applied.clear();
    }

    private void setRegion(int display, Region region) {
        Region last = applied.get(display);
        if (last != null && last.equals(region)) return;
        if (last == null && region.isEmpty() && display != Display.DEFAULT_DISPLAY) return;
        try {
            setTouchExplorationPassthroughRegion(display, region);
            applied.put(display, region);
        } catch (RuntimeException displayGone) {
            // a display that went away; nothing to hand touches to there
            applied.remove(display);
        }
    }
}
