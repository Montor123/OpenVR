package org.openvr.launcher;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.BatteryManager;
import android.os.StatFs;
import android.text.format.Formatter;

final class SystemSnapshot {
    private SystemSnapshot() {}

    static String battery(Context context) {
        Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (battery == null || !battery.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true)) {
            return context.getString(R.string.unavailable);
        }
        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        if (level < 0 || scale <= 0 || level > scale) {
            return context.getString(R.string.unavailable);
        }
        int percent = Math.round(level * 100f / scale);
        int state = battery.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN);
        if (state == BatteryManager.BATTERY_STATUS_CHARGING) {
            return context.getString(R.string.battery_charging, percent);
        }
        return context.getString(R.string.battery_percent, percent);
    }

    static String network(Context context) {
        ConnectivityManager manager = context.getSystemService(ConnectivityManager.class);
        if (manager == null) {
            return context.getString(R.string.unavailable);
        }
        try {
            Network active = manager.getActiveNetwork();
            if (active == null) {
                return context.getString(R.string.network_disconnected);
            }
            NetworkCapabilities details = manager.getNetworkCapabilities(active);
            if (details == null) {
                return context.getString(R.string.unavailable);
            }
            if (details.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                return context.getString(R.string.network_vpn);
            }
            if (details.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                return context.getString(R.string.settings_wifi);
            }
            if (details.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                return context.getString(R.string.network_ethernet);
            }
            if (details.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                return context.getString(R.string.network_cellular);
            }
            if (details.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) {
                return context.getString(R.string.settings_bluetooth);
            }
            return context.getString(R.string.network_connected);
        } catch (SecurityException exception) {
            return context.getString(R.string.unavailable);
        }
    }

    static String storage(Context context) {
        try {
            StatFs storage = new StatFs(context.getFilesDir().getPath());
            String free = Formatter.formatFileSize(context, storage.getAvailableBytes());
            String total = Formatter.formatFileSize(context, storage.getTotalBytes());
            return context.getString(R.string.storage_available, free, total);
        } catch (IllegalArgumentException exception) {
            return context.getString(R.string.unavailable);
        }
    }
}
