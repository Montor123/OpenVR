package org.openvr.demo;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private static final String TAG = "OpenVRDemo";

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);

        ScrollView page = new ScrollView(this);
        page.setFillViewport(true);
        page.setBackgroundColor(Color.rgb(18, 24, 36));

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_VERTICAL);
        int padding = Math.round(28 * getResources().getDisplayMetrics().density);
        content.setPadding(padding, padding, padding, padding);
        page.addView(content);

        TextView title = addText(content, getString(R.string.app_name), 30);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        addText(content, getString(R.string.description), 16);
        String device = "Android " + Build.VERSION.RELEASE
            + " · API " + Build.VERSION.SDK_INT + " · " + Build.CPU_ABI;
        addText(content, device, 14).setTypeface(Typeface.MONOSPACE);

        Button diagnostic = new Button(this);
        diagnostic.setText(R.string.diagnostic_action);
        content.addView(diagnostic);
        TextView status = addText(content, getString(R.string.ready), 14);

        diagnostic.setOnClickListener(view -> {
            Log.i(TAG, "DIAGNOSTIC_PRESSED " + device);
            status.setText(R.string.diagnostic_recorded);
        });
        setContentView(page);
        Log.i(TAG, "APP_READY " + device);
    }

    private TextView addText(LinearLayout parent, String text, int size) {
        TextView label = new TextView(this);
        label.setText(text);
        label.setTextColor(Color.rgb(237, 245, 255));
        label.setTextSize(size);
        int spacing = Math.round(10 * getResources().getDisplayMetrics().density);
        label.setPadding(0, 0, 0, spacing);
        parent.addView(label);
        return label;
    }
}
