document.documentElement.classList.add("js");
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08 },
  );
  document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));
} else
  document
    .querySelectorAll(".reveal")
    .forEach((el) => el.classList.add("visible"));

const steps = {
  capture: [
    "B starts area capture. Hold LT and move the stick to select. Y pastes the screenshot into your focused chat.",
    "Paste your screenshot with Y",
  ],
  dictate: [
    "RT triggers your dictation tool. Say what you want to change. Configure the trigger for the dictation shortcut you use.",
    "Your dictation shortcut → your words",
  ],
  send: [
    "Press the left stick to send Return. Keep moving, clicking, and working while your AI takes it from here.",
    "Return sent · over to your AI",
  ],
};
document.querySelectorAll("[data-step]").forEach((button) =>
  button.addEventListener("click", () => {
    document.querySelectorAll("[data-step]").forEach((other) => {
      const active = other === button;
      other.classList.toggle("active", active);
      other.setAttribute("aria-pressed", String(active));
    });
    document.querySelector(".demo-window").dataset.demo = button.dataset.step;
    document.querySelector("#workflow-caption").textContent =
      steps[button.dataset.step][0];
    document.querySelector(".compose-status").textContent =
      steps[button.dataset.step][1];
    document.querySelector(".demo-prompt").textContent =
      button.dataset.step === "capture"
        ? "Describe what you’d like to change…"
        : "Make this heading bigger, and give it a little more breathing room.";
  }),
);

const mappings = {
  screenshot: {
    xbox: ["B", 801, 285],
    playstation: ["Circle", 795, 280],
    category: "SCREEN CAPTURE",
    title: "Give your AI the full picture.",
    description:
      "Capture a region of your screen straight to the clipboard. Hold the left trigger to drag, then press the top face button to paste.",
    shortcut: "⌃ ⇧ ⌘ 4",
  },
  dictate: {
    xbox: ["RT", 712, 118],
    playstation: ["R2", 712, 118],
    category: "VOICE DICTATION",
    title: "Think it. Say it.",
    description:
      "Trigger your preferred dictation tool. Start with the Fn mapping, or record the shortcut you already use for voice input.",
    shortcut: "Fn · customizable",
  },
  drag: {
    xbox: ["LT", 288, 118],
    playstation: ["L2", 288, 118],
    category: "CLICK & DRAG",
    title: "Grab what matters.",
    description:
      "Hold the left trigger to hold the mouse button down. Move the stick to select a screenshot area, highlight text, or drag a window.",
    shortcut: "Hold left mouse button",
  },
  paste: {
    xbox: ["Y", 743, 227],
    playstation: ["Triangle", 737, 222],
    category: "PASTE",
    title: "Context, delivered.",
    description:
      "Paste copied text, screenshots, or OCR into the focused app. Hold RB / R1 for the alternate Control-V mapping.",
    shortcut: "⌘ V · RB / R1 + button: ⌃ V",
  },
  ocr: {
    xbox: ["X", 685, 285],
    playstation: ["Square", 679, 280],
    category: "TEXT RECOGNITION",
    title: "If you can see it, copy it.",
    description:
      "Drag over visible text with TextSniper or another OCR utility, then paste the recognized text. A separate OCR app is required.",
    shortcut: "⇧ ⌘ 2 · TextSniper starter mapping",
  },
  click: {
    xbox: ["A", 743, 343],
    playstation: ["Cross", 737, 338],
    category: "MOUSE CLICK",
    title: "A familiar point and click.",
    description:
      "Move the pointer with a stick and tap the bottom face button to click. No need to reach for the trackpad.",
    shortcut: "Left click",
  },
  enter: {
    xbox: ["L3", 283, 292],
    playstation: ["L3", 380, 420],
    category: "RETURN",
    title: "Send it.",
    description:
      "Press the left stick to send Return. Confirm a dialog, run a terminal command, or send a chat. Your focused app decides what Return does.",
    shortcut: "↩ Return",
  },
  backspace: {
    xbox: ["R3", 600, 420],
    playstation: ["R3", 620, 420],
    category: "BACKSPACE",
    title: "A little room to rethink.",
    description:
      "Press the right stick to send backward Delete. Correct the last character without moving your hands to the keyboard.",
    shortcut: "⌫ Backspace",
  },
  modifier: {
    xbox: ["LB", 288, 171],
    playstation: ["L1", 288, 171],
    category: "MODIFIER LAYERS",
    title: "Hold for more.",
    description:
      "Tap the left bumper for Escape. Hold it with a D-pad direction to cross a screen edge, or add your own alternate button actions.",
    shortcut: "LB / L1 + D-pad → cross edge",
  },
  copy: {
    xbox: ["View", 446, 296],
    playstation: ["Create", 351, 232],
    category: "COPY",
    title: "Keep that thought.",
    description:
      "Copy the current selection. Your usual copy-and-paste workflow, mapped to a button you can find by feel.",
    shortcut: "⌘ C",
  },
};
let family = "xbox",
  selectedMapping = "screenshot",
  selectedColor = "pink";
const originalStops = new Map();
document
  .querySelectorAll(".controller-svg stop")
  .forEach((stop) => originalStops.set(stop, stop.getAttribute("stop-color")));
const palettes = {
  pink: ["#F5A7C5", "#DA608F", "#962C59"],
  white: ["#FFFFFF", "#DFE1E1", "#9DA4AA"],
};

function paintController() {
  document
    .querySelectorAll(".controller-svg stop")
    .forEach((stop) =>
      stop.setAttribute("stop-color", originalStops.get(stop)),
    );
  if (selectedColor !== "original") {
    for (const id of ["xbox-shell", "xbox-edge", "playstation-white"]) {
      document
        .querySelectorAll(`#${id} stop`)
        .forEach((stop, index) =>
          stop.setAttribute(
            "stop-color",
            palettes[selectedColor][index] || palettes[selectedColor][2],
          ),
        );
    }
  }
}
function selectMapping(key) {
  selectedMapping = key;
  const mapping = mappings[key];
  document.querySelector("#mapping-key").textContent = mapping[family][0];
  document.querySelector("#mapping-category").textContent = mapping.category;
  document.querySelector("#mapping-title").textContent = mapping.title;
  document.querySelector("#mapping-description").textContent =
    mapping.description;
  document.querySelector("#mapping-shortcut").textContent = mapping.shortcut;
  document
    .querySelectorAll(".hotspot")
    .forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.mapping === key),
      ),
    );
}
function renderController() {
  document.querySelector("#xbox-art").hidden = family !== "xbox";
  document.querySelector("#playstation-art").hidden = family !== "playstation";
  document.querySelector(".controller-canvas").dataset.controller = family;
  const container = document.querySelector("#control-hotspots");
  container.replaceChildren();
  for (const [key, mapping] of Object.entries(mappings)) {
    const [label, x, y] = mapping[family];
    const button = document.createElement("button");
    button.className = "hotspot";
    button.dataset.mapping = key;
    button.style.left = `${x / 10}%`;
    button.style.top = `${y / 6.6}%`;
    button.setAttribute(
      "aria-label",
      `${label}: ${mapping.category.toLowerCase()}`,
    );
    const tooltip = document.createElement("span");
    tooltip.className = "hotspot-label";
    tooltip.textContent = label;
    tooltip.setAttribute("aria-hidden", "true");
    button.append(tooltip);
    button.addEventListener("click", () => selectMapping(key));
    container.append(button);
  }
  selectMapping(selectedMapping);
  paintController();
}
document.querySelectorAll("[data-family]").forEach((button) =>
  button.addEventListener("click", () => {
    family = button.dataset.family;
    document
      .querySelectorAll("[data-family]")
      .forEach((other) =>
        other.setAttribute("aria-pressed", String(other === button)),
      );
    renderController();
  }),
);
document.querySelectorAll("[data-color]").forEach((button) =>
  button.addEventListener("click", () => {
    selectedColor = button.dataset.color;
    document
      .querySelectorAll("[data-color]")
      .forEach((other) =>
        other.setAttribute("aria-pressed", String(other === button)),
      );
    paintController();
  }),
);
renderController();

let screen = 0;
document.querySelector("#handoff-next").addEventListener("click", () => {
  screen = (screen + 1) % 3;
  document.querySelector(".mac-scene").dataset.screen = screen;
  document.querySelector("#handoff-status").textContent = [
    "Pointer on the lead Mac",
    "Pointer on the second Mac",
    "Pointer on another Mac",
  ][screen];
});

// No analytics, cookies, API requests, keyboard hooks, or real controller access.
// The page only demonstrates the app; it cannot send input to your desktop.
