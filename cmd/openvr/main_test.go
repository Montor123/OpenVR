package main

import (
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGuestSettings(t *testing.T) {
	t.Setenv("OPENVR_ADB", "")
	t.Setenv("OPENVR_ANDROID", "1")
	t.Setenv("OPENVR_GUEST", "")
	t.Setenv("OPENVR_ANDROID_SERIAL", "127.0.0.1:6520")
	mode, _, serial, err := guestSettings()
	if err != nil || mode != "emulator" || serial != "emulator-5554" {
		t.Fatalf("default emulator settings: guest=%q serial=%q err=%v", mode, serial, err)
	}

	t.Setenv("OPENVR_GUEST", "cuttlefish")
	for _, candidate := range []string{"", "emulator-5554", "192.168.1.5:6520", "0.0.0.0:6520", "127.0.0.1:0", "127.0.0.1:65536"} {
		t.Setenv("OPENVR_ANDROID_SERIAL", candidate)
		if _, _, _, err := guestSettings(); err == nil {
			t.Errorf("accepted unexpected Cuttlefish transport %q", candidate)
		}
	}
	t.Setenv("OPENVR_ANDROID_SERIAL", "127.0.0.1:6520")
	mode, adb, serial, err := guestSettings()
	if err != nil || mode != "cuttlefish" || adb != "adb" || serial != "127.0.0.1:6520" {
		t.Fatalf("cuttlefish settings: guest=%q adb=%q serial=%q err=%v", mode, adb, serial, err)
	}
}

func TestCuttlefishAPKRequiresBootAndExpectedProduct(t *testing.T) {
	dir := t.TempDir()
	adb := filepath.Join(dir, "adb")
	calls := filepath.Join(dir, "calls")
	t.Setenv("FIXTURE_CALLS", calls)
	t.Setenv("ADB_SERVER_SOCKET", "tcp:wrong.example:5037")
	if err := os.WriteFile(adb, []byte(`#!/bin/sh
[ "$1" = -s ] && [ "$2" = "127.0.0.1:6520" ] || exit 91
[ -z "${ADB_SERVER_SOCKET+x}" ] || exit 93
shift 2
echo "$1 $2" >> "$FIXTURE_CALLS"
case "$*" in
  'shell getprop sys.boot_completed') [ "$FIXTURE_BOOT" != offline ] && echo "$FIXTURE_BOOT" ;;
  'shell getprop ro.product.product.name') echo "$FIXTURE_PRODUCT" ;;
  'shell getprop ro.product.cpu.abi') echo "$FIXTURE_ABI" ;;
  'logcat -d -t 200') echo 'registro Android simulado' ;;
  'install -r '*) [ "$(cat "$3")" = "fixture apk" ] && echo Success ;;
  *) exit 92 ;;
esac
`), 0700); err != nil {
		t.Fatal(err)
	}
	app := &server{
		guest: "cuttlefish", adb: adb, serial: "127.0.0.1:6520",
		results: dir, log: log.New(io.Discard, "", 0),
	}
	handler := app.routes()
	request := func(method, path, body string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, "http://localhost"+path, strings.NewReader(body))
		if method == http.MethodPost {
			req.Header.Set("Content-Type", "application/vnd.android.package-archive")
		}
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		return res
	}
	tests := []struct {
		boot, product, abi string
		state              string
	}{
		{"offline", cuttlefishProduct, "x86_64", "disconnected"},
		{"0", cuttlefishProduct, "x86_64", "booting"},
		{"1", "aosp_cf_x86_64_phone", "x86_64", "wrong-guest"},
		{"1", cuttlefishProduct, "arm64-v8a", "wrong-guest"},
		{"1", cuttlefishProduct, "x86_64", "ready"},
	}
	for _, tc := range tests {
		t.Setenv("FIXTURE_BOOT", tc.boot)
		t.Setenv("FIXTURE_PRODUCT", tc.product)
		t.Setenv("FIXTURE_ABI", tc.abi)
		status := request(http.MethodGet, "/api/status", "")
		if status.Code != http.StatusOK || !strings.Contains(status.Body.String(), `"bootState":"`+tc.state+`"`) {
			t.Fatalf("unexpected status for %s: %d %s", tc.state, status.Code, status.Body)
		}
		install := request(http.MethodPost, "/api/apk", "fixture apk")
		logs := request(http.MethodGet, "/api/logs?target=android", "")
		if tc.state == "ready" {
			if install.Code != http.StatusOK || !strings.Contains(install.Body.String(), "Success") ||
				logs.Code != http.StatusOK || !strings.Contains(logs.Body.String(), "registro Android simulado") {
				t.Fatalf("expected install and logs: %d %s, %d %s", install.Code, install.Body, logs.Code, logs.Body)
			}
		} else if install.Code != http.StatusServiceUnavailable || logs.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s unexpectedly accepted install or logs: %d, %d", tc.state, install.Code, logs.Code)
		}
	}
	invocations, err := os.ReadFile(calls)
	if err != nil {
		t.Fatal(err)
	}
	if got := string(invocations); strings.Count(got, "install -r\n") != 1 || strings.Count(got, "logcat -d\n") != 1 {
		t.Fatalf("ADB invoked outside the ready state: %s", got)
	}
}
