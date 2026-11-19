package org.openvr.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.LauncherApps;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Process;
import android.os.UserHandle;
import android.provider.Settings;
import android.text.Editable;
import android.text.InputType;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.Collator;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

public final class MainActivity extends Activity {
    private static final int BACKGROUND = 0xff10151e;
    private static final int SURFACE = 0xff1b2634;
    private static final int SURFACE_SELECTED = 0xff263c49;
    private static final int SURFACE_FOCUSED = 0xff293f50;
    private static final int OUTLINE = 0xff405464;
    private static final int PRIMARY = 0xfff4f6fa;
    private static final int SECONDARY = 0xffb6c6d6;
    private static final int ACCENT = 0xff8de2df;
    private static final int FAVORITE = 0xffffd391;

    private static final int HOME = 0;
    private static final int LIBRARY = 1;
    private static final int CONFIG = 2;
    private static final int RECENT_LIMIT = 8;
    private static final String FAVORITES_KEY = "favorites";
    private static final String RECENTS_KEY = "recents";
    private static final Pattern ACCENTS = Pattern.compile("\\p{M}+");
    private static final int[] TAB_IDS = {R.id.tab_home, R.id.tab_library, R.id.tab_settings};
    private static final int[] TAB_LABELS = {R.string.home, R.string.library, R.string.settings};

    private final Map<String, AppEntry> apps = new LinkedHashMap<>();
    private final Set<String> favorites = new HashSet<>();
    private final List<String> recents = new ArrayList<>();
    private final Button[] tabs = new Button[TAB_IDS.length];

    private PackageManager packageManager;
    private LauncherApps launcherApps;
    private SharedPreferences preferences;
    private LinearLayout libraryControls;
    private ScrollView scroll;
    private LinearLayout content;
    private EditText search;
    private Button appFilter;
    private Button gameFilter;
    private int columns;
    private int section;
    private boolean games;
    private String query = "";
    private int restoredScroll = -1;
    private int hatKey = KeyEvent.KEYCODE_UNKNOWN;

    private final LauncherApps.Callback packageCallback = new LauncherApps.Callback() {
        @Override public void onPackageAdded(String packageName, UserHandle user) {
            refreshForUser(user);
        }

        @Override public void onPackageRemoved(String packageName, UserHandle user) {
            refreshForUser(user);
        }

        @Override public void onPackageChanged(String packageName, UserHandle user) {
            refreshForUser(user);
        }

        @Override public void onPackagesAvailable(String[] packages, UserHandle user, boolean replacing) {
            refreshForUser(user);
        }

        @Override public void onPackagesUnavailable(String[] packages, UserHandle user, boolean replacing) {
            refreshForUser(user);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        packageManager = getPackageManager();
        launcherApps = getSystemService(LauncherApps.class);
        preferences = getSharedPreferences("launcher", MODE_PRIVATE);
        favorites.addAll(preferences.getStringSet(FAVORITES_KEY, Collections.emptySet()));
        String savedRecents = preferences.getString(RECENTS_KEY, "");
        if (!savedRecents.isEmpty()) {
            Collections.addAll(recents, savedRecents.split("\n", RECENT_LIMIT + 1));
        }
        if (state != null) {
            section = Math.max(HOME, Math.min(CONFIG, state.getInt("section", HOME)));
            games = state.getBoolean("games");
            query = state.getString("query", "");
            restoredScroll = state.getInt("scroll");
        }
        int width = getResources().getConfiguration().screenWidthDp;
        columns = width >= 900 ? 3 : width >= 580 ? 2 : 1;

        LinearLayout screen = column();
        screen.setBackgroundColor(BACKGROUND);
        screen.setPadding(dp(20), dp(14), dp(20), 0);
        setContentView(screen);

        TextView title = label(getString(R.string.app_name), 30, PRIMARY, true);
        screen.addView(title);

        LinearLayout navigation = row();
        navigation.setPadding(0, dp(10), 0, dp(10));
        for (int i = 0; i < tabs.length; i++) {
            int destination = i;
            tabs[i] = button(TAB_IDS[i], TAB_LABELS[i], () -> selectSection(destination));
            navigation.addView(tabs[i], spacedCell(i > 0));
        }
        screen.addView(navigation);

        libraryControls = column();
        screen.addView(libraryControls);
        buildLibraryControls();

        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setPadding(dp(2), dp(3), dp(2), dp(16));
        screen.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        content = column();
        scroll.addView(content);

        updateNavigation();
        if (!screen.isInTouchMode()) {
            tabs[section].requestFocus();
        }
    }

    private void buildLibraryControls() {
        LinearLayout filters = row();
        appFilter = button(R.id.library_apps, R.string.apps, () -> selectCategory(false));
        gameFilter = button(R.id.library_games, R.string.games, () -> selectCategory(true));
        filters.addView(appFilter, spacedCell(false));
        filters.addView(gameFilter, spacedCell(true));
        libraryControls.addView(filters);

        search = new EditText(this);
        search.setId(R.id.library_search);
        search.setHint(R.string.search_hint);
        search.setTextColor(PRIMARY);
        search.setHintTextColor(SECONDARY);
        search.setTextSize(16);
        search.setSingleLine(true);
        search.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        search.setImeOptions(EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING);
        search.setMinHeight(dp(54));
        search.setBackground(selectableSurface(12, false));
        search.setPadding(dp(14), 0, dp(14), 0);
        search.setText(query);
        LinearLayout.LayoutParams searchSize = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        searchSize.setMargins(0, dp(9), 0, dp(10));
        libraryControls.addView(search, searchSize);
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence text, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence text, int start, int before, int count) {
                query = text.toString();
                if (section == LIBRARY) {
                    render(0);
                }
            }

            @Override public void afterTextChanged(Editable text) {}
        });
        search.setOnKeyListener((view, key, event) -> {
            if (key != KeyEvent.KEYCODE_DPAD_UP && key != KeyEvent.KEYCODE_DPAD_DOWN) {
                return false;
            }
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                int direction = key == KeyEvent.KEYCODE_DPAD_UP ? View.FOCUS_UP : View.FOCUS_DOWN;
                View next = search.focusSearch(direction);
                if (next != null) {
                    next.requestFocus();
                }
            }
            return true;
        });
        search.setOnEditorActionListener((view, action, event) -> {
            if (action != EditorInfo.IME_ACTION_DONE) {
                return false;
            }
            hideKeyboard();
            View firstApp = content.findViewById(R.id.app_open);
            if (firstApp != null) {
                firstApp.requestFocus();
            }
            return true;
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
        hatKey = KeyEvent.KEYCODE_UNKNOWN;
        if (launcherApps != null) {
            launcherApps.unregisterCallback(packageCallback);
        }
        super.onStop();
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        state.putInt("section", section);
        state.putBoolean("games", games);
        state.putString("query", query);
        state.putInt("scroll", scroll.getScrollY());
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (section != HOME) {
            selectSection(HOME);
            tabs[HOME].requestFocus();
        }
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int mappedKey = event.getKeyCode();
        if (mappedKey == KeyEvent.KEYCODE_BUTTON_A) {
            mappedKey = KeyEvent.KEYCODE_DPAD_CENTER;
        } else if (mappedKey == KeyEvent.KEYCODE_BUTTON_B) {
            mappedKey = KeyEvent.KEYCODE_BACK;
        }
        if (mappedKey == event.getKeyCode()) {
            return super.dispatchKeyEvent(event);
        }
        return super.dispatchKeyEvent(new KeyEvent(
                event.getDownTime(), event.getEventTime(), event.getAction(), mappedKey,
                event.getRepeatCount(), event.getMetaState(), event.getDeviceId(),
                event.getScanCode(), event.getFlags(), event.getSource()));
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        if (!event.isFromSource(InputDevice.SOURCE_JOYSTICK)
                || event.getActionMasked() != MotionEvent.ACTION_MOVE) {
            return super.dispatchGenericMotionEvent(event);
        }
        float horizontal = event.getAxisValue(MotionEvent.AXIS_HAT_X);
        float vertical = event.getAxisValue(MotionEvent.AXIS_HAT_Y);
        int direction = KeyEvent.KEYCODE_UNKNOWN;
        if (Math.abs(horizontal) > 0.5f) {
            direction = horizontal > 0 ? KeyEvent.KEYCODE_DPAD_RIGHT : KeyEvent.KEYCODE_DPAD_LEFT;
        } else if (Math.abs(vertical) > 0.5f) {
            direction = vertical > 0 ? KeyEvent.KEYCODE_DPAD_DOWN : KeyEvent.KEYCODE_DPAD_UP;
        }
        int previous = hatKey;
        hatKey = direction;
        if (direction != KeyEvent.KEYCODE_UNKNOWN && direction != previous) {
            dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, direction));
            dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, direction));
        }
        return direction != KeyEvent.KEYCODE_UNKNOWN || previous != KeyEvent.KEYCODE_UNKNOWN
                || super.dispatchGenericMotionEvent(event);
    }

    private void selectSection(int destination) {
        if (destination == section) {
            return;
        }
        if (section == LIBRARY) {
            hideKeyboard();
        }
        section = destination;
        updateNavigation();
        render(0);
    }

    private void selectCategory(boolean showGames) {
        if (games != showGames) {
            games = showGames;
            updateNavigation();
            render(0);
        }
    }

    private void updateNavigation() {
        for (int i = 0; i < tabs.length; i++) {
            styleButton(tabs[i], i == section);
        }
        libraryControls.setVisibility(section == LIBRARY ? View.VISIBLE : View.GONE);
        styleButton(appFilter, !games);
        styleButton(gameFilter, games);
    }

    private void refreshForUser(UserHandle user) {
        if (Process.myUserHandle().equals(user)) {
            loadApps();
        }
    }

    private void loadApps() {
        Intent launcherIntent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        Set<ComponentName> seen = new HashSet<>();
        List<AppEntry> discovered = new ArrayList<>();
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
                String name = TextUtils.isEmpty(label) ? component.getPackageName() : label.toString();
                discovered.add(new AppEntry(component, name, entry));
            }
        }

        Collator alphabet = Collator.getInstance();
        discovered.sort((left, right) -> {
            int result = alphabet.compare(left.name, right.name);
            return result != 0 ? result : left.component.compareTo(right.component);
        });
        apps.clear();
        for (AppEntry entry : discovered) {
            apps.put(entry.key, entry);
        }
        int position = restoredScroll >= 0 ? restoredScroll : scroll.getScrollY();
        restoredScroll = -1;
        render(position);
    }

    private void render(int scrollPosition) {
        View focused = getCurrentFocus();
        Object focusTag = focused == null ? null : focused.getTag();
        content.removeAllViews();
        if (section == HOME) {
            renderHome();
        } else if (section == LIBRARY) {
            renderLibrary();
        } else {
            renderSettings();
        }
        scroll.post(() -> {
            scroll.scrollTo(0, scrollPosition);
            View target = focusTag == null ? null : content.findViewWithTag(focusTag);
            if (target != null && !scroll.isInTouchMode()) {
                target.requestFocus();
            }
        });
    }

    private void renderHome() {
        heading(R.string.favorites);
        List<AppEntry> pinned = new ArrayList<>();
        for (AppEntry entry : apps.values()) {
            if (favorites.contains(entry.key)) {
                pinned.add(entry);
            }
        }
        appendGrid(pinned, R.string.no_favorites, "favorite");

        heading(R.string.recents);
        List<AppEntry> launched = new ArrayList<>();
        for (String key : recents) {
            AppEntry entry = apps.get(key);
            if (entry != null) {
                launched.add(entry);
            }
        }
        appendGrid(launched, R.string.no_recents, "recent");
    }

    private void renderLibrary() {
        String needle = normalize(query.trim());
        List<AppEntry> matched = new ArrayList<>();
        for (AppEntry entry : apps.values()) {
            if (entry.game == games && entry.searchKey.contains(needle)) {
                matched.add(entry);
            }
        }

        if (!needle.isEmpty()) {
            appendGrid(matched, R.string.no_matches, "library");
        } else {
            appendGrid(matched, games ? R.string.no_games : R.string.no_apps, "library");
        }
    }

    private void appendGrid(List<AppEntry> entries, int emptyLabel, String group) {
        if (entries.isEmpty()) {
            TextView empty = label(getString(emptyLabel), 16, SECONDARY, false);
            empty.setPadding(dp(14), dp(15), dp(14), dp(15));
            empty.setBackground(surface(14, SURFACE, OUTLINE, 1));
            content.addView(empty);
            return;
        }
        LinearLayout current = null;
        for (int i = 0; i < entries.size(); i++) {
            int column = i % columns;
            if (column == 0) {
                current = row();
                LinearLayout.LayoutParams spacing = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                spacing.bottomMargin = dp(9);
                content.addView(current, spacing);
            }
            current.addView(appCard(entries.get(i), group), spacedCell(column > 0));
        }
        int remainder = entries.size() % columns;
        if (remainder > 0) {
            for (int i = remainder; i < columns; i++) {
                current.addView(new View(this), spacedCell(true));
            }
        }
    }

    private View appCard(AppEntry entry, String group) {
        LinearLayout card = row();
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setBackground(surface(14, SURFACE, OUTLINE, 1));
        card.setPadding(dp(4), dp(4), dp(4), dp(4));

        LinearLayout open = row();
        open.setId(R.id.app_open);
        open.setTag(group + ":open:" + entry.key);
        open.setGravity(Gravity.CENTER_VERTICAL);
        open.setMinimumHeight(dp(65));
        open.setPadding(dp(9), dp(6), dp(7), dp(6));
        open.setBackground(selectableSurface(10, false));
        open.setFocusable(true);
        open.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        open.setContentDescription(getString(R.string.app_accessibility, entry.name, entry.key));
        open.setOnClickListener(view -> openApp(entry));

        ImageView icon = new ImageView(this);
        icon.setImageDrawable(entry.activity.loadIcon(packageManager));
        icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        open.addView(icon, new LinearLayout.LayoutParams(dp(38), dp(38)));

        LinearLayout text = column();
        text.setPaddingRelative(dp(10), 0, 0, 0);
        TextView name = label(entry.name, 16, PRIMARY, true);
        name.setId(R.id.app_label);
        name.setMaxLines(2);
        name.setEllipsize(TextUtils.TruncateAt.END);
        name.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        text.addView(name);
        TextView packageLabel = label(entry.component.getPackageName(), 12, SECONDARY, false);
        packageLabel.setSingleLine(true);
        packageLabel.setEllipsize(TextUtils.TruncateAt.END);
        packageLabel.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        text.addView(packageLabel);
        open.addView(text, spacedCell(false));
        card.addView(open, spacedCell(false));

        Button pin = button(R.id.app_favorite, R.string.favorite_empty, () -> toggleFavorite(entry));
        pin.setTag(group + ":pin:" + entry.key);
        boolean pinned = favorites.contains(entry.key);
        pin.setText(pinned ? R.string.favorite_filled : R.string.favorite_empty);
        styleButton(pin, pinned);
        pin.setTextColor(pinned ? FAVORITE : SECONDARY);
        pin.setTextSize(22);
        pin.setPadding(0, 0, 0, 0);
        int description = pinned ? R.string.favorite_remove : R.string.favorite_add;
        pin.setContentDescription(getString(description, entry.name));
        card.addView(pin, new LinearLayout.LayoutParams(dp(48), dp(52)));
        return card;
    }

    private void toggleFavorite(AppEntry app) {
        if (!favorites.remove(app.key)) {
            favorites.add(app.key);
        }
        preferences.edit().putStringSet(FAVORITES_KEY, new HashSet<>(favorites)).apply();
        render(scroll.getScrollY());
    }

    private void openApp(AppEntry app) {
        hideKeyboard();
        if (!launch(Intent.makeMainActivity(app.component), app.name)) {
            loadApps();
            return;
        }
        recents.remove(app.key);
        recents.add(0, app.key);
        while (recents.size() > RECENT_LIMIT) {
            recents.remove(recents.size() - 1);
        }
        preferences.edit().putString(RECENTS_KEY, String.join("\n", recents)).apply();
    }

    private void renderSettings() {
        heading(R.string.device_status);
        LinearLayout status = column();
        status.setPadding(dp(14), dp(12), dp(14), dp(12));
        status.setBackground(surface(14, SURFACE, OUTLINE, 1));
        status.addView(statusLine(R.string.battery, SystemSnapshot.battery(this)));
        status.addView(statusLine(R.string.network, SystemSnapshot.network(this)));
        status.addView(statusLine(R.string.storage, SystemSnapshot.storage(this)));
        content.addView(status);

        heading(R.string.settings_system);
        settingsButton(R.id.settings_android, R.string.settings_android, Settings.ACTION_SETTINGS);
        settingsButton(R.id.settings_wifi, R.string.settings_wifi, Settings.ACTION_WIFI_SETTINGS);
        settingsButton(R.id.settings_bluetooth, R.string.settings_bluetooth, Settings.ACTION_BLUETOOTH_SETTINGS);
        settingsButton(R.id.settings_display, R.string.settings_display, Settings.ACTION_DISPLAY_SETTINGS);
        settingsButton(R.id.settings_sound, R.string.settings_sound, Settings.ACTION_SOUND_SETTINGS);
        settingsButton(R.id.settings_storage, R.string.settings_storage, Settings.ACTION_INTERNAL_STORAGE_SETTINGS);
        appendSetting(button(R.id.settings_info, R.string.system, this::showSystemInfo));
    }

    private View statusLine(int name, String value) {
        LinearLayout line = row();
        line.setGravity(Gravity.CENTER_VERTICAL);
        line.setMinimumHeight(dp(36));
        line.addView(label(getString(name), 15, SECONDARY, false), spacedCell(false));
        TextView detail = label(value, 15, PRIMARY, true);
        detail.setGravity(Gravity.END);
        line.addView(detail);
        return line;
    }

    private void settingsButton(int id, int name, String action) {
        appendSetting(button(id, name, () -> launch(new Intent(action), getString(name))));
    }

    private void appendSetting(Button button) {
        button.setTag("setting:" + button.getId());
        button.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams size = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        size.bottomMargin = dp(7);
        content.addView(button, size);
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

    private boolean launch(Intent intent, String name) {
        try {
            startActivity(intent);
            return true;
        } catch (ActivityNotFoundException | SecurityException exception) {
            Toast.makeText(this, getString(R.string.launch_failed, name), Toast.LENGTH_SHORT).show();
            return false;
        }
    }

    private void hideKeyboard() {
        InputMethodManager keyboard = getSystemService(InputMethodManager.class);
        if (keyboard != null) {
            keyboard.hideSoftInputFromWindow(search.getWindowToken(), 0);
        }
    }

    private void heading(int resource) {
        TextView title = label(getString(resource), 20, PRIMARY, true);
        title.setPadding(0, dp(8), 0, dp(9));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            title.setAccessibilityHeading(true);
        }
        content.addView(title);
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

    private Button button(int id, int resource, Runnable action) {
        Button button = new Button(this);
        button.setId(id);
        button.setText(resource);
        button.setTextSize(15);
        button.setAllCaps(false);
        button.setPaddingRelative(dp(10), dp(7), dp(10), dp(7));
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setMinHeight(dp(52));
        button.setMinimumHeight(dp(52));
        button.setFocusable(true);
        button.setOnClickListener(view -> action.run());
        styleButton(button, false);
        return button;
    }

    private void styleButton(Button button, boolean selected) {
        button.setTextColor(selected ? ACCENT : PRIMARY);
        button.setSelected(selected);
        button.setBackground(selectableSurface(10, selected));
    }

    private LinearLayout.LayoutParams spacedCell(boolean addMargin) {
        LinearLayout.LayoutParams cell = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        if (addMargin) {
            cell.setMarginStart(dp(8));
        }
        return cell;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        return layout;
    }

    private StateListDrawable selectableSurface(int radius, boolean selected) {
        StateListDrawable background = new StateListDrawable();
        background.addState(new int[]{android.R.attr.state_focused}, surface(radius, SURFACE_FOCUSED, ACCENT, 2));
        background.addState(new int[]{android.R.attr.state_pressed}, surface(radius, SURFACE_FOCUSED, ACCENT, 1));
        background.addState(new int[0], surface(radius, selected ? SURFACE_SELECTED : SURFACE,
                selected ? ACCENT : OUTLINE, 1));
        return background;
    }

    private GradientDrawable surface(int radius, int color, int border, int width) {
        GradientDrawable background = new GradientDrawable();
        background.setColor(color);
        background.setCornerRadius(dp(radius));
        background.setStroke(dp(width), border);
        return background;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static String normalize(String value) {
        return ACCENTS.matcher(Normalizer.normalize(value.toLowerCase(Locale.ROOT), Normalizer.Form.NFD))
                .replaceAll("");
    }

    private static final class AppEntry {
        final ComponentName component;
        final String key;
        final String name;
        final ResolveInfo activity;
        final String searchKey;
        final boolean game;

        @SuppressWarnings("deprecation")
        AppEntry(ComponentName component, String name, ResolveInfo activity) {
            this.component = component;
            key = component.flattenToShortString();
            this.name = name;
            this.activity = activity;
            searchKey = normalize(name + " " + component.getPackageName());
            ApplicationInfo info = activity.activityInfo.applicationInfo;
            game = info.category == ApplicationInfo.CATEGORY_GAME
                    || (info.category == ApplicationInfo.CATEGORY_UNDEFINED
                    && (info.flags & ApplicationInfo.FLAG_IS_GAME) != 0);
        }
    }
}
