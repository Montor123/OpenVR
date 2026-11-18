const RADIANS = Math.PI / 180;
const NEAR = 0.09;
const FLOOR = 0;
const BACK = -7;
const SIDE = 7;
const CEILING = 4.4;
const TARGET = [0, 1.45, -1.1];
const TARGET_RADIUS = 0.58;
const RAY_DEPTH = 6.7;
const HAND_COLORS = ["#66e3ce", "#b49bff"];
const HAND_NAMES = ["izquierdo", "derecho"];

const clamp = (value, low, high) => Math.min(high, Math.max(low, value));

function clipAtNear(start, end) {
  const t = (NEAR - start[2]) / (end[2] - start[2]);
  return [start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t, NEAR];
}

function shortAngle(angle) {
  return Math.atan2(Math.sin(angle), Math.cos(angle));
}

function poseText(x, y, z) {
  return `X ${x.toFixed(2)}  Y ${y.toFixed(2)}  Z ${z.toFixed(2)}`;
}

function makeCamera({ x, y, z, yaw, pitch }, width, height) {
  const cosYaw = Math.cos(yaw);
  const sinYaw = Math.sin(yaw);
  const cosPitch = Math.cos(pitch);
  const sinPitch = Math.sin(pitch);
  const focal = height * 0.85;

  return {
    focal,
    transform(point) {
      const dx = point[0] - x;
      const dy = point[1] - y;
      const dz = point[2] - z;
      const depth = dx * sinYaw - dz * cosYaw;
      return [
        dx * cosYaw + dz * sinYaw,
        dy * cosPitch - depth * sinPitch,
        dy * sinPitch + depth * cosPitch,
      ];
    },
    project([horizontal, vertical, depth]) {
      return [width / 2 + horizontal * focal / depth, height / 2 - vertical * focal / depth];
    },
  };
}

function polygon(ctx, camera, points, fill, stroke) {
  const transformed = points.map(camera.transform);
  const clipped = [];
  for (const [index, end] of transformed.entries()) {
    const start = transformed[(index + transformed.length - 1) % transformed.length];
    if ((start[2] >= NEAR) !== (end[2] >= NEAR)) clipped.push(clipAtNear(start, end));
    if (end[2] >= NEAR) clipped.push(end);
  }
  if (clipped.length < 3) return;

  ctx.beginPath();
  for (const [index, point] of clipped.entries()) {
    const [x, y] = camera.project(point);
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fillStyle = fill;
  ctx.fill();
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = 1;
    ctx.stroke();
  }
}

function line(ctx, camera, a, b, color, width = 1) {
  let start = camera.transform(a);
  let end = camera.transform(b);
  if (start[2] < NEAR && end[2] < NEAR) return;
  if (start[2] < NEAR) start = clipAtNear(start, end);
  if (end[2] < NEAR) end = clipAtNear(end, start);
  ctx.beginPath();
  ctx.moveTo(...camera.project(start));
  ctx.lineTo(...camera.project(end));
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
}

function ring(centerX, y, centerZ, radius, count = 24) {
  return Array.from({ length: count }, (_, index) => {
    const angle = index * 2 * Math.PI / count;
    return [centerX + radius * Math.cos(angle), y, centerZ + radius * Math.sin(angle)];
  });
}

function drawRoom(ctx, camera, warm) {
  const wall = warm ? "#30262e" : "#232b49";
  const side = warm ? "#241f2a" : "#192037";
  const floor = warm ? "#2a202c" : "#1c243b";
  const trim = warm ? "#c17954" : "#727da9";

  polygon(ctx, camera, [[-SIDE, FLOOR, BACK], [SIDE, FLOOR, BACK], [SIDE, CEILING, BACK], [-SIDE, CEILING, BACK]], wall);
  polygon(ctx, camera, [[-SIDE, FLOOR, SIDE], [-SIDE, FLOOR, BACK], [-SIDE, CEILING, BACK], [-SIDE, CEILING, SIDE]], side);
  polygon(ctx, camera, [[SIDE, FLOOR, BACK], [SIDE, FLOOR, SIDE], [SIDE, CEILING, SIDE], [SIDE, CEILING, BACK]], side);
  polygon(ctx, camera, [[-SIDE, FLOOR, SIDE], [SIDE, FLOOR, SIDE], [SIDE, CEILING, SIDE], [-SIDE, CEILING, SIDE]], wall);
  polygon(ctx, camera, [[-SIDE, CEILING, BACK], [SIDE, CEILING, BACK], [SIDE, CEILING, SIDE], [-SIDE, CEILING, SIDE]], "#14192a");
  polygon(ctx, camera, [[-SIDE, FLOOR, SIDE], [SIDE, FLOOR, SIDE], [SIDE, FLOOR, BACK], [-SIDE, FLOOR, BACK]], floor);

  for (let grid = -SIDE; grid <= SIDE; grid++) {
    const gridColor = warm ? "#8b65554b" : "#8798d147";
    line(ctx, camera, [-SIDE, FLOOR, grid], [SIDE, FLOOR, grid], gridColor);
    line(ctx, camera, [grid, FLOOR, BACK], [grid, FLOOR, SIDE], gridColor);
  }

  for (const z of [BACK, SIDE]) {
    line(ctx, camera, [-SIDE, 0.22, z], [SIDE, 0.22, z], trim);
    line(ctx, camera, [-SIDE, CEILING - 0.18, z], [SIDE, CEILING - 0.18, z], trim);
    for (const x of [-5.3, -4.9, 4.9, 5.3]) {
      line(ctx, camera, [x, 0.36, z], [x, 3.83, z], trim, 2);
    }
  }
  for (const x of [-SIDE, SIDE]) {
    line(ctx, camera, [x, 0.22, BACK], [x, 0.22, SIDE], trim);
    line(ctx, camera, [x, CEILING - 0.18, BACK], [x, CEILING - 0.18, SIDE], trim);
  }

  const panelZ = BACK + 0.012;
  polygon(ctx, camera, [[-3.7, 1.27, panelZ], [3.7, 1.27, panelZ], [3.7, 3.82, panelZ], [-3.7, 3.82, panelZ]], "#151b2c", trim);
  for (const x of [-2.7, -2.45, 2.45, 2.7]) {
    line(ctx, camera, [x, 2, panelZ], [x, 3.15, panelZ], "#6978a7", 2);
  }
  const title = camera.transform([0, 2.75, panelZ]);
  if (title[2] > 2) {
    const [x, y] = camera.project(title);
    ctx.textAlign = "center";
    ctx.fillStyle = "#bec8e7";
    ctx.font = `600 ${clamp(0.68 * camera.focal / title[2], 13, 54)}px system-ui`;
    ctx.fillText("OpenVR", x, y);
    ctx.fillStyle = "#9aa6ce";
    ctx.font = `600 ${clamp(0.25 * camera.focal / title[2], 9, 20)}px system-ui`;
    ctx.fillText("SALA DE CALIBRACIÓN", x, y + clamp(0.45 * camera.focal / title[2], 11, 32));
  }
}

function drawTarget(ctx, camera, exercise, hits) {
  polygon(ctx, camera, ring(0, 0, TARGET[2], 2.25), "#6c76b521", "#778ac28c");
  polygon(ctx, camera, ring(0, 0.008, TARGET[2], 1.48), "#41486b40", "#977be3a6");

  const base = ring(0, 0.022, TARGET[2], 1.02, 8);
  const top = ring(0, 0.25, TARGET[2], 0.88, 8);
  const faces = base.map((corner, index) => {
    const next = (index + 1) % base.length;
    const points = [corner, base[next], top[next], top[index]];
    const depth = points.reduce((sum, vertex) => sum + camera.transform(vertex)[2], 0) / 4;
    return { points, depth };
  });
  faces.sort((a, b) => b.depth - a.depth);
  for (const face of faces) polygon(ctx, camera, face.points, "#2e3552", "#6c759e");
  polygon(ctx, camera, top, "#454e76", "#8d9bca");

  const position = camera.transform(TARGET);
  if (position[2] <= NEAR) return;
  const [x, y] = camera.project(position);
  const radius = Math.min(170, camera.focal * TARGET_RADIUS / position[2]);
  const hue = exercise ? (hits % 2 ? "#66e3ce" : "#b49bff") : "#f6cd7d";
  const glow = ctx.createRadialGradient(x, y, 0, x, y, radius * 1.85);
  glow.addColorStop(0, hue + "4e");
  glow.addColorStop(0.55, hue + "28");
  glow.addColorStop(1, hue + "00");
  ctx.fillStyle = glow;
  ctx.fillRect(x - radius * 1.85, y - radius * 1.85, radius * 3.7, radius * 3.7);
  ctx.beginPath();
  ctx.ellipse(x, y, radius * 1.18, radius * 0.55, -0.48, 0, Math.PI * 2);
  ctx.strokeStyle = hue + "9b";
  ctx.lineWidth = 1.4;
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(x, y, radius * 0.78, 0, Math.PI * 2);
  const orb = ctx.createRadialGradient(x - radius * 0.29, y - radius * 0.31, 0, x, y, radius);
  orb.addColorStop(0, "#fff0d9");
  orb.addColorStop(0.43, hue);
  orb.addColorStop(1, "#515583");
  ctx.fillStyle = orb;
  ctx.fill();
  ctx.strokeStyle = hue;
  ctx.stroke();
}

function drawHand(ctx, camera, hand, index, active, height) {
  const [x, y] = camera.project([hand.x, hand.y, hand.depth]);
  const [rayX, rayY] = camera.project([hand.aimX * RAY_DEPTH, hand.aimY * RAY_DEPTH, RAY_DEPTH]);
  const color = HAND_COLORS[index];
  const unit = clamp((height / 460) / hand.depth, 0.34, 1.35);

  if (active) {
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(rayX, rayY);
    ctx.setLineDash([3, 5]);
    ctx.strokeStyle = color + "a0";
    ctx.lineWidth = 1.6;
    ctx.stroke();
    ctx.setLineDash([]);

    ctx.beginPath();
    ctx.arc(rayX, rayY, 5, 0, Math.PI * 2);
    ctx.strokeStyle = color;
    ctx.stroke();
  }

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(index === 0 ? 0.22 : -0.22);
  ctx.scale(unit, unit);

  ctx.beginPath();
  ctx.roundRect(-12, -3, 24, 49, 9);
  ctx.fillStyle = "#222841";
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = active ? color : color + "85";
  ctx.stroke();

  ctx.beginPath();
  ctx.ellipse(0, -10, 23, 13, 0, 0, Math.PI * 2);
  ctx.fillStyle = "#262f49";
  ctx.fill();
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(0, -10, 4, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();

  ctx.restore();
}

export function initScene() {
  const viewport = document.querySelector("#viewport");
  const canvas = document.querySelector("#scene");
  const context = canvas.getContext("2d", { alpha: false });
  const menu = document.querySelector("#scene-menu");
  const menuButton = document.querySelector("#menu-button");
  const sceneMessage = document.querySelector("#scene-message");
  const trackingStatus = document.querySelector("#tracking-status");
  const trackingApp = document.querySelector("#tracking-app");
  const lightingButton = document.querySelector("#lighting-button");
  const headPose = document.querySelector("#head-pose");
  const handPose = document.querySelector("#hand-pose");
  const handButtons = [document.querySelector("#left-hand"), document.querySelector("#right-hand")];
  const movementKeys = new Set(["w", "a", "s", "d", "q", "e", "i", "j", "k", "l", "u", "o", "arrowleft", "arrowright", "arrowup", "arrowdown"]);
  const keys = new Set();
  let headset;
  let hands;
  let selectedHand = 0;
  let warm = false;
  let exercise = false;
  let hits = 0;
  let pointer = null;
  let frame = null;
  let lastTime = null;

  function invalidate() {
    if (frame === null) frame = requestAnimationFrame(render);
  }

  function reset() {
    headset = { x: 0, y: 1.65, z: 5.6, yaw: 0, pitch: -0.045 };
    hands = [
      { x: -0.44, y: -0.31, depth: 1.01, aimX: 0, aimY: 0 },
      { x: 0.44, y: -0.31, depth: 1.01, aimX: 0, aimY: 0 },
    ];
    setHand(0);
  }

  function setMessage(message) {
    sceneMessage.hidden = !message;
    sceneMessage.textContent = message;
  }

  function setHand(index) {
    selectedHand = index;
    for (const [buttonIndex, button] of handButtons.entries()) {
      button.setAttribute("aria-pressed", buttonIndex === index ? "true" : "false");
    }
    invalidate();
  }

  function showMenu(show) {
    menu.hidden = !show;
    menuButton.setAttribute("aria-expanded", String(show));
    menuButton.firstChild.textContent = show ? "Cerrar menú " : "Abrir menú ";
    keys.clear();
    if (show) trackingApp.focus({ preventScroll: true });
    else viewport.focus({ preventScroll: true });
  }

  function trigger() {
    if (!exercise) {
      setMessage("Abre el menú con M e inicia la prueba de seguimiento");
      return;
    }

    const hand = hands[selectedHand];
    const camera = makeCamera(headset, canvas.clientWidth, canvas.clientHeight);
    const [horizontal, vertical, depth] = camera.transform(TARGET);
    const travel = depth - hand.depth;
    const amount = travel / (RAY_DEPTH - hand.depth);
    const x = hand.x + (hand.aimX * RAY_DEPTH - hand.x) * amount;
    const y = hand.y + (hand.aimY * RAY_DEPTH - hand.y) * amount;
    const distance = Math.hypot(horizontal - x, vertical - y);
    if (travel > 0 && distance <= TARGET_RADIUS) {
      hits++;
      trackingStatus.textContent = `Aciertos · ${hits}`;
      setMessage(`Objetivo alcanzado con el mando ${HAND_NAMES[selectedHand]}`);
    } else {
      setMessage("Alinea el punto del rayo con la esfera y vuelve a pulsar Intro");
    }
    invalidate();
  }

  function integrate(seconds) {
    const axis = (positive, negative) => Number(keys.has(positive)) - Number(keys.has(negative));
    const moveX = axis("d", "a") * seconds * 2;
    const moveZ = axis("w", "s") * seconds * 2;
    headset.yaw = shortAngle(headset.yaw + axis("arrowright", "arrowleft") * seconds * 1.45);
    headset.pitch = clamp(headset.pitch + axis("arrowup", "arrowdown") * seconds * 1.1, -1.15, 1.15);
    headset.x = clamp(headset.x + moveX * Math.cos(headset.yaw) + moveZ * Math.sin(headset.yaw), -6.3, 6.3);
    headset.z = clamp(headset.z + moveX * Math.sin(headset.yaw) - moveZ * Math.cos(headset.yaw), -6.3, 6.3);
    headset.y = clamp(headset.y + axis("e", "q") * seconds * 1.2, 0.45, 3.55);

    const hand = hands[selectedHand];
    hand.x = clamp(hand.x + axis("l", "j") * seconds * 0.8, -0.62, 0.62);
    hand.y = clamp(hand.y + axis("o", "u") * seconds * 0.7, -0.45, 0.25);
    hand.depth = clamp(hand.depth + axis("i", "k") * seconds * 0.6, 0.8, 1.6);
    hand.aimX = (hand.x - (selectedHand === 0 ? -0.44 : 0.44)) * 0.55;
    hand.aimY = (hand.y + 0.31) * 0.55;
  }

  function render(now) {
    frame = null;
    if (keys.size) integrate(Math.min(0.04, (now - (lastTime ?? now)) / 1000));
    lastTime = keys.size ? now : null;

    const width = viewport.clientWidth;
    const height = viewport.clientHeight;
    if (!width || !height || !context) return;
    const ratio = Math.min(window.devicePixelRatio, 2);
    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
    }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.fillStyle = "#131727";
    context.fillRect(0, 0, width, height);
    const camera = makeCamera(headset, width, height);
    drawRoom(context, camera, warm);
    drawTarget(context, camera, exercise, hits);

    const shade = context.createRadialGradient(width / 2, height / 2, height * 0.27, width / 2, height / 2, Math.hypot(width, height) / 2);
    shade.addColorStop(0, "#0f102400");
    shade.addColorStop(1, "#0c0e20b0");
    context.fillStyle = shade;
    context.fillRect(0, 0, width, height);
    drawHand(context, camera, hands[1 - selectedHand], 1 - selectedHand, false, height);
    drawHand(context, camera, hands[selectedHand], selectedHand, true, height);

    const head = poseText(headset.x, headset.y, headset.z)
      + `\nGiro ${(headset.yaw / RADIANS).toFixed(1)}°  Inclinación ${(headset.pitch / RADIANS).toFixed(1)}°`;
    const hand = hands[selectedHand];
    const pose = poseText(hand.x, hand.y, -hand.depth);
    if (headPose.value !== head) headPose.value = head;
    if (handPose.value !== pose) handPose.value = pose;
    if (keys.size) invalidate();
  }

  viewport.addEventListener("keydown", (event) => {
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    const key = event.key.toLowerCase();
    if ((key === "m" || (key === "escape" && !menu.hidden)) && !event.repeat) {
      event.preventDefault();
      showMenu(menu.hidden);
      return;
    }
    if (!menu.hidden) return;
    if (movementKeys.has(key)) {
      event.preventDefault();
      keys.add(key);
      setMessage("");
      invalidate();
    } else if ((key === "1" || key === "2") && !event.repeat) {
      setHand(Number(key) - 1);
    } else if (key === "enter" && !event.repeat) {
      event.preventDefault();
      trigger();
    }
  });
  window.addEventListener("keyup", (event) => keys.delete(event.key.toLowerCase()));
  window.addEventListener("blur", () => keys.clear());
  viewport.addEventListener("focus", () => setMessage(""));
  viewport.addEventListener("blur", () => keys.clear());
  viewport.addEventListener("pointerdown", (event) => {
    if (!menu.hidden || !event.isPrimary || event.button !== 0) return;
    viewport.focus({ preventScroll: true });
    viewport.setPointerCapture(event.pointerId);
    pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
    viewport.classList.add("dragging");
  });
  viewport.addEventListener("pointermove", (event) => {
    if (pointer?.id !== event.pointerId) return;
    headset.yaw = shortAngle(headset.yaw + (event.clientX - pointer.x) * 0.005);
    headset.pitch = clamp(headset.pitch - (event.clientY - pointer.y) * 0.005, -1.15, 1.15);
    pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
    invalidate();
  });
  viewport.addEventListener("lostpointercapture", () => {
    pointer = null;
    viewport.classList.remove("dragging");
  });

  for (const [index, button] of handButtons.entries()) {
    button.addEventListener("click", () => {
      setHand(index);
      if (menu.hidden) viewport.focus({ preventScroll: true });
    });
  }
  menuButton.addEventListener("click", () => showMenu(menu.hidden));
  document.querySelector("#close-menu").addEventListener("click", () => showMenu(false));
  document.querySelector("#reset-button").addEventListener("click", () => reset());
  document.querySelector("#menu-reset").addEventListener("click", () => {
    reset();
    showMenu(false);
  });

  lightingButton.addEventListener("click", () => {
    warm = !warm;
    lightingButton.setAttribute("aria-pressed", String(warm));
    invalidate();
  });
  trackingApp.addEventListener("click", () => {
    exercise = !exercise;
    hits = 0;
    trackingApp.setAttribute("aria-pressed", String(exercise));
    trackingApp.textContent = exercise ? "Cerrar prueba de seguimiento" : "Iniciar prueba de seguimiento";
    trackingStatus.textContent = exercise ? "Aciertos · 0" : "Seguimiento simulado";
    showMenu(false);
    if (exercise) setMessage("Alinea el punto del rayo con la esfera y pulsa Intro");
    invalidate();
  });

  if (context) {
    new ResizeObserver(invalidate).observe(viewport);
    reset();
  } else {
    setMessage("Canvas no está disponible en este navegador");
  }
}
