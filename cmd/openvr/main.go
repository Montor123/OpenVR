package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	openvr "github.com/Montor123/OpenVR"
)

const maxAPK = 256 << 20
const maxLog = 64 << 10

type server struct {
	android   bool
	adb       string
	results   string
	log       *log.Logger
	operation sync.Mutex
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func main() {
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		client := http.Client{Timeout: 2 * time.Second}
		res, err := client.Get("http://127.0.0.1:8080/healthz")
		if err != nil {
			log.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != http.StatusOK {
			log.Fatal(res.Status)
		}
		return
	}

	app := &server{
		android: os.Getenv("OPENVR_ANDROID") == "1",
		adb:     env("OPENVR_ADB", "/data/android/sdk/platform-tools/adb"),
		results: env("OPENVR_RESULTS", "/data/results"),
		log:     log.New(os.Stdout, "", log.LstdFlags|log.LUTC),
	}
	path := filepath.Join(app.results, "demo.log")
	if info, err := os.Stat(path); err == nil && info.Size() > maxLog {
		if err := os.Rename(path, path+".1"); err != nil {
			app.log.Print(err)
		}
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err == nil {
		defer file.Close()
		app.log.SetOutput(io.MultiWriter(os.Stdout, file))
	} else {
		app.log.Printf("Registro persistente no disponible: %v", err)
	}

	httpServer := &http.Server{
		Addr: ":8080", Handler: app.routes(),
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 3 * time.Minute,
		WriteTimeout: 6 * time.Minute, IdleTimeout: 30 * time.Second,
		MaxHeaderBytes: 16 << 10,
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(shutdown); err != nil {
			app.log.Print(err)
		}
	}()
	app.log.Printf("OpenVR iniciado en el puerto 8080 (Android habilitado: %t)", app.android)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		app.log.Fatal(err)
	}
}

func (app *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	})
	mux.HandleFunc("GET /api/status", app.status)
	mux.HandleFunc("GET /api/logs", app.logs)
	mux.HandleFunc("POST /api/apk", app.apk)
	mux.HandleFunc("POST /api/demo", app.demo)
	mux.HandleFunc("POST /api/launch", func(w http.ResponseWriter, r *http.Request) {
		app.androidAction(w, r, app.launchDemo)
	})
	mux.Handle("GET /", http.FileServerFS(openvr.Web()))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if hostname, _, err := net.SplitHostPort(host); err == nil {
			host = hostname
		}
		switch host {
		case "localhost", "127.0.0.1", "::1", "[::1]":
		default:
			http.Error(w, "Solo se admite acceso local", http.StatusForbidden)
			return
		}
		if r.Method == http.MethodPost {
			origin := r.Header.Get("Origin")
			if (origin != "" && origin != "http://"+r.Host) || r.Header.Get("Sec-Fetch-Site") == "cross-site" {
				http.Error(w, "Origen no autorizado", http.StatusForbidden)
				return
			}
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		if r.URL.Path == "/healthz" || strings.HasPrefix(r.URL.Path, "/api/") {
			w.Header().Set("Cache-Control", "no-store")
		}
		mux.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, code int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(value)
}

func fail(w http.ResponseWriter, code int, message string) {
	writeJSON(w, code, map[string]string{"error": message})
}

func (app *server) runADB(ctx context.Context, args ...string) (string, error) {
	command := exec.CommandContext(ctx, app.adb, append([]string{"-s", "emulator-5554"}, args...)...)
	output, err := command.CombinedOutput()
	content := strings.TrimSpace(string(output))
	if len(content) > maxLog {
		content = content[len(content)-maxLog:]
	}
	if err != nil {
		if ctx.Err() != nil {
			return content, ctx.Err()
		}
		return content, fmt.Errorf("%w: %s", err, content)
	}
	return content, nil
}

func (app *server) ready(ctx context.Context) bool {
	if !app.android {
		return false
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	state, err := app.runADB(ctx, "shell", "getprop", "sys.boot_completed")
	return err == nil && (state == "1" || strings.HasSuffix(state, "\n1"))
}

func (app *server) status(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]bool{
		"android": app.ready(r.Context()), "desktop": app.android,
	})
}

func tail(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", err
	}
	if info.Size() > maxLog {
		if _, err := file.Seek(-maxLog, io.SeekEnd); err != nil {
			return "", err
		}
	}
	data, err := io.ReadAll(io.LimitReader(file, maxLog))
	return string(data), err
}

func (app *server) logs(w http.ResponseWriter, r *http.Request) {
	var logText string
	var err error
	switch r.URL.Query().Get("target") {
	case "", "demo":
		logText, err = tail(filepath.Join(app.results, "demo.log"))
	case "android":
		if !app.android {
			fail(w, http.StatusServiceUnavailable, "Android está disponible en el perfil dev.")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		logText, err = app.runADB(ctx, "logcat", "-d", "-t", "200")
		if err != nil {
			logText, err = tail(filepath.Join(app.results, "android-emulator.log"))
		}
	default:
		fail(w, http.StatusBadRequest, "Registro desconocido.")
		return
	}
	if err != nil {
		logText = "Aún no hay registros disponibles."
	}
	writeJSON(w, http.StatusOK, map[string]string{"log": logText})
}

func (app *server) androidAction(w http.ResponseWriter, r *http.Request, action func(context.Context) (string, error)) {
	if !app.ready(r.Context()) {
		fail(w, http.StatusServiceUnavailable, "Inicia Android en el perfil dev y espera a que termine el arranque.")
		return
	}
	if !app.operation.TryLock() {
		fail(w, http.StatusConflict, "Hay otra operación Android en curso.")
		return
	}
	defer app.operation.Unlock()
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
	defer cancel()
	output, err := action(ctx)
	if err != nil {
		app.log.Printf("Operación Android fallida: %v", err)
		fail(w, http.StatusBadGateway, err.Error())
		return
	}
	app.log.Print("Operación Android completada")
	writeJSON(w, http.StatusOK, map[string]string{"output": output})
}

func (app *server) apk(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Content-Type") != "application/vnd.android.package-archive" {
		fail(w, http.StatusUnsupportedMediaType, "Selecciona un archivo APK.")
		return
	}
	app.androidAction(w, r, func(ctx context.Context) (string, error) {
		r.Body = http.MaxBytesReader(w, r.Body, maxAPK)
		defer r.Body.Close()
		file, err := os.CreateTemp("", "openvr-*.apk")
		if err != nil {
			return "", err
		}
		defer os.Remove(file.Name())
		size, copyErr := io.Copy(file, r.Body)
		closeErr := file.Close()
		if copyErr != nil {
			return "", copyErr
		}
		if closeErr != nil {
			return "", closeErr
		}
		if size == 0 {
			return "", errors.New("El APK está vacío.")
		}
		return app.runADB(ctx, "install", "-r", file.Name())
	})
}

func (app *server) launchDemo(ctx context.Context) (string, error) {
	output, err := app.runADB(ctx, "shell", "am", "start", "-W", "-n", "org.openvr.demo/.MainActivity")
	if err == nil && !strings.Contains(output, "Status: ok") {
		err = fmt.Errorf("Android no confirmó la apertura: %s", output)
	}
	return output, err
}

func (app *server) demo(w http.ResponseWriter, r *http.Request) {
	app.androidAction(w, r, func(ctx context.Context) (string, error) {
		apk := filepath.Join(app.results, "openvr-demo.apk")
		if _, err := os.Stat(apk); err != nil {
			return "", errors.New("Compila el APK de ejemplo con android/build-apk.sh antes de instalarlo.")
		}
		output, err := app.runADB(ctx, "install", "-r", apk)
		if err != nil {
			return "", err
		}
		launch, err := app.launchDemo(ctx)
		return output + "\n" + launch, err
	})
}
