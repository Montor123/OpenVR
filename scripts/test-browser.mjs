import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname } from "node:path";

const { chromium } = await import(process.env.OPENVR_PLAYWRIGHT ?? "playwright");
const baseUrl = process.env.OPENVR_URL;
const screenshot = process.env.OPENVR_SCREENSHOT;
const web = new URL("../web/", import.meta.url);
const assets = new Set(["/", "/app.js", "/scene.js", "/style.css"]);
const mime = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript" };
const posts = new Map();
let online = false;
let failStatus = false;
let failLogs = false;

function fixtureServer() {
  return createServer(async (req, res) => {
    const url = new URL(req.url, "http://localhost");
    const json = (body, status = 200) => {
      res.writeHead(status, { "Content-Type": "application/json" });
      res.end(JSON.stringify(body));
    };

    if (url.pathname === "/api/status") {
      if (failStatus) return json({ error: "Servicio en pausa" }, 503);
      return json({ android: online, desktop: online });
    }
    if (url.pathname === "/api/logs") {
      if (failLogs) return json({ error: "Registro interrumpido" }, 503);
      return json({ log: `registro de ${url.searchParams.get("target")}` });
    }
    if (req.method === "POST" && ["/api/demo", "/api/launch", "/api/apk"].includes(url.pathname)) {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      if (posts.has("/api/launch") && url.pathname === "/api/launch") {
        return json({ error: "El ejemplo se cerró" }, 409);
      }
      posts.set(url.pathname, { contentType: req.headers["content-type"], body: Buffer.concat(chunks) });
      return json({ output: `ADB simulado ${url.pathname}` });
    }
    if (assets.has(url.pathname)) {
      const asset = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
      const body = await readFile(new URL(asset, web));
      res.writeHead(200, { "Content-Type": mime[extname(asset)] });
      return res.end(body);
    }
    return json({ error: "Ruta inexistente" }, 404);
  });
}

async function testScene(page) {
  const head = page.locator("#head-pose");
  const hand = page.locator("#hand-pose");
  await page.waitForFunction(() => document.querySelector("#hand-pose").value.includes("X"));
  const initialHead = await head.evaluate((element) => element.value);
  const initialLeft = await hand.evaluate((element) => element.value);
  await page.locator("#viewport").focus();
  await page.keyboard.down("w");
  await page.waitForFunction((initial) => document.querySelector("#head-pose").value !== initial, initialHead);
  await page.keyboard.up("w");
  await page.keyboard.press("2");
  await page.waitForFunction((initial) => document.querySelector("#hand-pose").value !== initial, initialLeft);
  const initialRight = await hand.evaluate((element) => element.value);
  await page.keyboard.down("j");
  await page.waitForFunction((initial) => document.querySelector("#hand-pose").value !== initial, initialRight);
  await page.keyboard.up("j");
  await page.keyboard.press("1");
  await page.waitForFunction((initial) => document.querySelector("#hand-pose").value === initial, initialLeft);
  await page.keyboard.press("2");
  await page.waitForFunction((initial) => document.querySelector("#hand-pose").value !== initial, initialLeft);
  assert.notEqual(await hand.evaluate((element) => element.value), initialRight);

  const viewport = await page.locator("#viewport").boundingBox();
  const canvas = page.locator("#scene");
  const beforeDrag = await canvas.evaluate((element) => element.toDataURL());
  await page.mouse.move(viewport.x + 200, viewport.y + 135);
  await page.mouse.down();
  await page.mouse.move(viewport.x + 275, viewport.y + 160);
  await page.mouse.up();
  await page.waitForFunction((before) => document.querySelector("#scene").toDataURL() !== before, beforeDrag);
  await page.locator("#reset-button").click();
  await page.waitForFunction((initial) => document.querySelector("#head-pose").value === initial, initialHead);
  await page.locator("#viewport").focus();
  await page.keyboard.press("m");
  await page.getByRole("button", { name: "Iniciar prueba de seguimiento" }).click();
  await page.keyboard.press("Enter");
  await page.getByText("Aciertos · 1", { exact: true }).waitFor();
  await page.locator("#menu-button").click();
  await page.getByRole("button", { name: "Cambiar iluminación" }).click();
  assert.equal(await page.locator("#lighting-button").getAttribute("aria-pressed"), "true");
  await page.keyboard.press("Escape");
  assert(await page.locator("#scene-menu").isHidden());
  console.log("OK: sala Canvas, movimiento por teclado y ratón, poses de dos mandos, menú y objetivo.");
}

async function testFixtureApi(page) {
  await page.getByText("ADB sin conexión", { exact: true }).waitFor();
  await page.getByText("registro de demo", { exact: true }).waitFor();
  assert(await page.locator("#install-apk").isDisabled());
  online = true;
  await page.getByText("ADB listo", { exact: true }).waitFor({ timeout: 10000 });
  assert.equal(await page.locator("#desktop-link").getAttribute("href"), "http://127.0.0.1:6080/vnc.html?autoconnect=true&resize=scale");
  const testApk = Buffer.from([80, 75, 3, 4]);
  await page.locator("#apk-file").setInputFiles({ name: "ejemplo.apk", mimeType: "application/vnd.android.package-archive", buffer: testApk });
  await page.locator("#install-apk").click();
  await page.getByText("ADB simulado /api/apk", { exact: true }).waitFor();
  assert.deepEqual(posts.get("/api/apk"), { contentType: "application/vnd.android.package-archive", body: testApk });
  await page.locator("#install-demo").click();
  await page.getByText("ADB simulado /api/demo", { exact: true }).waitFor();
  await page.locator("#launch-demo").click();
  await page.getByText("ADB simulado /api/launch", { exact: true }).waitFor();
  await page.locator("#log-target").selectOption("android");
  await page.getByText("registro de android", { exact: true }).waitFor();
  console.log("OK: carga APK binaria, ejemplo, registros y enlace noVNC con API de prueba.");

  await page.locator("#launch-demo").click();
  await page.getByText("El ejemplo se cerró", { exact: true }).waitFor();
  assert(await page.locator("#apk-output.error").isVisible());
  assert(await page.locator("#launch-demo").isEnabled());
  failLogs = true;
  await page.locator("#refresh-logs").click();
  await page.getByText(/No se pudieron cargar los registros. Registro interrumpido/).waitFor();
  failStatus = true;
  await page.getByText("Servidor sin conexión", { exact: true }).waitFor({ timeout: 10000 });
  assert(await page.locator("#install-apk").isDisabled());
  assert(await page.locator("#desktop-link").isHidden());
  console.log("OK: errores de ADB, registros y servidor tratados en la interfaz.");
}

async function testLiveApi(page, base) {
  const health = await page.request.get(new URL("/healthz", base).href);
  assert(health.ok());
  assert.deepEqual(await health.json(), { ok: true });
  const response = await page.request.get(new URL("/api/logs?target=demo", base).href);
  assert(response.ok());
  const { log } = await response.json();
  assert.equal(typeof log, "string");
  assert.equal(await page.locator("#logs").textContent(), log || "Sin registros disponibles.");
  console.log("OK: servicio real disponible y registro visible en la página.");
}

const fixture = baseUrl ? null : fixtureServer();
if (fixture) await new Promise((resolve) => fixture.listen(0, "127.0.0.1", resolve));
const url = baseUrl ?? `http://127.0.0.1:${fixture.address().port}/`;
let browser;
try {
  browser = await chromium.launch({ executablePath: process.env.OPENVR_CHROMIUM, headless: true });
  const page = await browser.newPage({ viewport: { width: 1380, height: 980 }, locale: "es-ES" });
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(url);
  await testScene(page);
  await page.waitForFunction(() => document.querySelector("#logs").getAttribute("aria-busy") === "false");
  if (baseUrl) await testLiveApi(page, baseUrl);
  if (screenshot) await page.screenshot({ path: screenshot, fullPage: true });
  if (fixture) await testFixtureApi(page);

  await page.setViewportSize({ width: 390, height: 820 });
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  assert.deepEqual(errors, []);
  console.log(`OK: Chromium ${browser.version()}, sin excepciones JS ni desbordamiento a 390 px.`);
} finally {
  await browser?.close();
  fixture?.close();
}
