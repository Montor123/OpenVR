package org.openvr.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.LauncherApps;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Process;
import android.os.UserHandle;
import android.provider.Settings;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.Collator;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public final class MainActivity extends Activity {
    private static final int BACKGROUND = 0xff0f1724;
    private static final int SURFACE = 0xff18293d;
    private static final int OUTLINE = 0xff375269;
    private static final int PRIMARY = 0xfff2f5f8;
    private static final int SECONDARY = 0xffb4c4d4;
    private static final int ACCENT = 0xff7bd9ea;

    private static final String SAVED_QUERY = "query";
    private static final String SAVED_SCROLL = "scroll";

    private final List<AppEntry> apps = new ArrayList<>();
    private PackageManager packageManager;
    private LauncherApps launcherApps;
    private EditText search;
    private ScrollView scroll;
    private LinearLayout appList;
    private int columns;
    private int restoredScroll = -1;

    private final LauncherApps.Callback packageCallback = new LauncherApps.Callback() {
        @Override
        public void onPackageAdded(String packageName, UserHandle user) {
            refreshForUser(user);
        }

        @Override
        public void onPackageRemoved(String packageName, UserHandle user) {
            refreshForUser(user);
        }

        @Override
        public void onPackageChanged(String packageName, UserHandle user) {
            refreshForUser(user);
        }

        @Override
        public void onPackagesAvailable(String[] packages, UserHandle user, boolean replacing) {
            refreshForUser(user);
        }

        @Override
        public void onPackagesUnavailable(String[] packages, UserHandle user, boolean replacing) {
            refreshForUser(user);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        packageManager = getPackageManager();
        launcherApps = getSystemService(LauncherApps.class);
        columns = getResources().getConfiguration().screenWidthDp >= 580 ? 2 : 1;

        LinearLayout screen = new LinearLayout(this);
        screen.setOrientation(LinearLayout.VERTICAL);
        screen.setBackgroundColor(BACKGROUND);
        screen.setPadding(dp(20), dp(16), dp(20), 0);
        screen.setFocusableInTouchMode(true);
        setContentView(screen);
        screen.requestFocus();

        TextView title = label(getString(R.string.app_name), 32, PRIMARY, true);
        screen.addView(title);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(actionButton(R.string.settings,
                () -> launch(new Intent(Settings.ACTION_SETTINGS), getString(R.string.settings))));
        actions.addView(actionButton(R.string.system, this::showSystemInfo));
        screen.addView(actions);

        search = new EditText(this);
        search.setHint(R.string.search_hint);
        search.setTextColor(PRIMARY);
        search.setHintTextColor(SECONDARY);
        search.setTextSize(16);
        search.setSingleLine(true);
        search.setInputType(InputType.TYPE_CLASS_TEXT);
        search.setImeOptions(EditorInfo.IME_ACTION_DONE);
        search.setMinHeight(dp(48));
        search.setBackground(roundedSurface(12));
        search.setPadding(dp(14), 0, dp(14), 0);
        LinearLayout.LayoutParams searchSize = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        searchSize.setMargins(0, dp(12), 0, dp(14));
        screen.addView(search, searchSize);
        if (state != null) {
            search.setText(state.getString(SAVED_QUERY, ""));
            restoredScroll = state.getInt(SAVED_SCROLL);
        }

        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        screen.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        appList = new LinearLayout(this);
        appList.setOrientation(LinearLayout.VERTICAL);
        appList.setPadding(0, 0, 0, dp(16));
        scroll.addView(appList);

        search.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence text, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence text, int start, int before, int count) {
                renderApps(false);
            }

            @Override
            public void afterTextChanged(Editable text) {}
        });
    }

    @Override
    protected void onStart() {
        super.onStart();
        if (launcherApps != null) {
            launcherApps.registerCallback(packageCallback);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        loadApps();
    }

    @Override
    protected void onStop() {
        if (launcherApps != null) {
            launcherApps.unregisterCallback(packageCallback);
        }
        super.onStop();
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        state.putString(SAVED_QUERY, search.getText().toString());
        state.putInt(SAVED_SCROLL, scroll.getScrollY());
    }

    private void refreshForUser(UserHandle user) {
        if (Process.myUserHandle().equals(user)) {
            loadApps();
        }
    }

    private void loadApps() {
        Intent launcherIntent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        Set<ComponentName> seen = new HashSet<>();
        apps.clear();

        for (ResolveInfo entry : packageManager.queryIntentActivities(launcherIntent, 0)) {
            if (entry.activityInfo == null || !entry.activityInfo.exported
                    || getPackageName().equals(entry.activityInfo.packageName)) {
                continue;
            }
            String permission = entry.activityInfo.permission;
            if (permission != null && checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                continue;
            }

            ComponentName component = new ComponentName(
                    entry.activityInfo.packageName, entry.activityInfo.name);
            if (seen.add(component)) {
                CharSequence label = entry.loadLabel(packageManager);
                String name = label != null ? label.toString() : component.getPackageName();
                apps.add(new AppEntry(component, name, entry));
            }
        }

        Collator alphabet = Collator.getInstance();
        apps.sort((left, right) -> {
            int result = alphabet.compare(left.name, right.name);
            return result != 0 ? result : left.component.compareTo(right.component);
        });
        renderApps(true);
    }

    private void renderApps(boolean keepScroll) {
        String query = search.getText().toString().trim().toLowerCase(Locale.ROOT);
        int previousScroll = restoredScroll >= 0 ? restoredScroll : scroll.getScrollY();
        int scrollTarget = keepScroll ? previousScroll : 0;
        restoredScroll = -1;
        appList.removeAllViews();
        LinearLayout row = null;
        int visible = 0;
        for (AppEntry entry : apps) {
            if (!entry.searchKey.contains(query)) {
                continue;
            }
            if (visible % columns == 0) {
                row = new LinearLayout(this);
                row.setOrientation(LinearLayout.HORIZONTAL);
                appList.addView(row);
            }
            LinearLayout.LayoutParams cell = new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1);
            cell.setMarginEnd(columns == 2 && visible % columns == 0 ? dp(10) : 0);
            cell.bottomMargin = dp(10);
            row.addView(appCard(entry), cell);
            visible++;
        }

        if (visible == 0) {
            appList.addView(label(getString(query.isEmpty() ? R.string.no_apps : R.string.no_matches),
                    16, SECONDARY, false));
        } else if (columns == 2 && visible % 2 != 0) {
            row.addView(new View(this), new LinearLayout.LayoutParams(0, 0, 1));
        }
        scroll.post(() -> scroll.scrollTo(0, scrollTarget));
    }

    private View appCard(AppEntry entry) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setMinimumHeight(dp(72));
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackground(new RippleDrawable(ColorStateList.valueOf(0x427bd9ea),
                roundedSurface(14), null));
        card.setFocusable(true);
        card.setContentDescription(getString(R.string.app_accessibility,
                entry.name, entry.component.getPackageName()));

        ImageView icon = new ImageView(this);
        icon.setImageDrawable(entry.activity.loadIcon(packageManager));
        icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        card.addView(icon, new LinearLayout.LayoutParams(dp(44), dp(44)));

        LinearLayout text = new LinearLayout(this);
        text.setOrientation(LinearLayout.VERTICAL);
        text.setPaddingRelative(dp(12), 0, 0, 0);
        text.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        text.addView(label(entry.name, 16, PRIMARY, true));
        text.addView(label(entry.component.getPackageName(), 12, SECONDARY, false));
        card.addView(text, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        card.setOnClickListener(view -> {
            Intent intent = Intent.makeMainActivity(entry.component);
            launch(intent, entry.name);
        });
        return card;
    }

    private TextView label(String value, int size, int color, boolean bold) {
        TextView text = new TextView(this);
        text.setText(value);
        text.setTextSize(size);
        text.setTextColor(color);
        if (bold) {
            text.setTypeface(Typeface.DEFAULT_BOLD);
        }
        return text;
    }

    private Button actionButton(int resource, Runnable action) {
        Button button = new Button(this);
        button.setText(resource);
        button.setTextColor(ACCENT);
        button.setAllCaps(false);
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private GradientDrawable roundedSurface(int radius) {
        GradientDrawable background = new GradientDrawable();
        background.setColor(SURFACE);
        background.setCornerRadius(dp(radius));
        background.setStroke(dp(1), OUTLINE);
        return background;
    }

    private void showSystemInfo() {
        String details = getString(R.string.system_details,
                Build.MODEL, Build.VERSION.RELEASE, Build.VERSION.SDK_INT,
                String.join(", ", Build.SUPPORTED_ABIS), Build.DISPLAY);
        new AlertDialog.Builder(this)
                .setTitle(R.string.system_title)
                .setMessage(details)
                .setPositiveButton(android.R.string.ok, null)
                .show();
    }

    private void launch(Intent intent, String name) {
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException | SecurityException exception) {
            Toast.makeText(this, getString(R.string.launch_failed, name), Toast.LENGTH_SHORT).show();
            loadApps();
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class AppEntry {
        final ComponentName component;
        final String name;
        final ResolveInfo activity;
        final String searchKey;

        AppEntry(ComponentName component, String name, ResolveInfo activity) {
            this.component = component;
            this.name = name;
            this.activity = activity;
            searchKey = (name + " " + component.getPackageName()).toLowerCase(Locale.ROOT);
        }
    }
}
