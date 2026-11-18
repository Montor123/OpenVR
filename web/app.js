import { initScene } from "./scene.js";

const androidDot = document.querySelector("#android-dot");
const androidLabel = document.querySelector("#android-status-label");
const apkForm = document.querySelector("#apk-form");
const apkFile = document.querySelector("#apk-file");
const installApk = document.querySelector("#install-apk");
const installDemo = document.querySelector("#install-demo");
const launchDemo = document.querySelector("#launch-demo");
const apkHint = document.querySelector("#apk-hint");
const apkOutput = document.querySelector("#apk-output");
const desktopLink = document.querySelector("#desktop-link");
const logSelect = document.querySelector("#log-target");
const logs = document.querySelector("#logs");

let androidReady = false;
let busy = false;
let logRequest = 0;

async function request(path, options = {}) {
  const response = await fetch(path, { cache: "no-store", ...options });
  const type = response.headers.get("content-type") ?? "";
  if (!type.startsWith("application/json")) {
    throw new Error(response.ok ? "Formato de respuesta inesperado." : `HTTP ${response.status}`);
  }
  const data = await response.json();
  if (!response.ok || data.error) throw new Error(data.error ?? `HTTP ${response.status}`);
  return data;
}

function updateButtons() {
  const disabled = !androidReady || busy;
  for (const element of [apkFile, installApk, installDemo, launchDemo]) element.disabled = disabled;
}

async function refreshStatus() {
  try {
    const status = await request("/api/status");
    androidReady = status.android === true;
    androidLabel.textContent = androidReady ? "ADB listo" : "ADB sin conexión";
    apkHint.textContent = androidReady
      ? "Abre tus APK instaladas desde el escritorio Android."
      : "Inicia el emulador desde el perfil dev para habilitar ADB.";
    if (status.desktop === true) {
      const url = new URL("http://localhost:6080/vnc.html?autoconnect=true&resize=scale");
      url.hostname = window.location.hostname;
      desktopLink.href = url.href;
      desktopLink.hidden = false;
    } else {
      desktopLink.hidden = true;
    }
  } catch {
    androidReady = false;
    androidLabel.textContent = "Servidor sin conexión";
    apkHint.textContent = "Comprueba que el servidor local esté en ejecución.";
    desktopLink.hidden = true;
  }
  androidDot.classList.toggle("live", androidReady);
  updateButtons();
}

async function refreshLogs() {
  const current = ++logRequest;
  const target = logSelect.value;
  logs.setAttribute("aria-busy", "true");
  let value;
  try {
    const data = await request(`/api/logs?target=${encodeURIComponent(target)}`);
    value = data.log || "Sin registros disponibles.";
  } catch (error) {
    value = `No se pudieron cargar los registros. ${error.message}`;
  }
  if (logRequest !== current) return;
  logs.textContent = value;
  logs.setAttribute("aria-busy", "false");
}

async function runAndroid(path, options = {}) {
  if (busy || !androidReady) return;
  busy = true;
  updateButtons();
  apkOutput.hidden = false;
  apkOutput.classList.remove("error");
  apkOutput.textContent = "Ejecutando mediante ADB…";
  try {
    const result = await request(path, { method: "POST", ...options });
    apkOutput.textContent = result.output || "Operación completada.";
  } catch (error) {
    apkOutput.textContent = error.message;
    apkOutput.classList.add("error");
  } finally {
    busy = false;
    updateButtons();
    refreshLogs();
  }
}

apkForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const file = apkFile.files[0];
  if (!file) return;
  if (!file.name.toLowerCase().endsWith(".apk")) {
    apkOutput.hidden = false;
    apkOutput.classList.add("error");
    apkOutput.textContent = "Selecciona un archivo .apk.";
    return;
  }
  runAndroid("/api/apk", {
    headers: { "Content-Type": "application/vnd.android.package-archive" },
    body: file,
  });
});
installDemo.addEventListener("click", () => runAndroid("/api/demo"));
launchDemo.addEventListener("click", () => runAndroid("/api/launch"));
logSelect.addEventListener("change", refreshLogs);
document.querySelector("#refresh-logs").addEventListener("click", refreshLogs);

initScene();
refreshStatus();
refreshLogs();
window.setInterval(refreshStatus, 5000);
