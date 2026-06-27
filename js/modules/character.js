import { navigate, goHome } from '../nav.js';

const FRAME_W = 64;
const FRAME_H = 64;
const FRAME_COUNT = 5;
const FPS = 8;
const CANVAS_SIZE = 384;
const SHIRT_KEY = 'character-shirt';

const SHIRT_OPTIONS = [
  { id: 'blue',   label: 'Blue',   targetHue: null },
  { id: 'red',    label: 'Red',    targetHue: 0,   src: 'assets/Sprites/Clothes/Shirts/Red_Shirt.png' },
  { id: 'yellow', label: 'Yellow', targetHue: 52,  src: 'assets/Sprites/Clothes/Shirts/Yellow_Shirt.png' },
  { id: 'green',  label: 'Green',  targetHue: 130, src: 'assets/Sprites/Clothes/Shirts/Green_Shirt.png' },
];

let _animGen = 0;
const _sheetCache = {};

export function getSelectedShirt() {
  return localStorage.getItem(SHIRT_KEY) || 'blue';
}

export function handleCharacter() {
  navigate(renderCharacterScreen);
}

function renderCharacterScreen(container) {
  _animGen++;
  const selected = getSelectedShirt();

  container.innerHTML = `
    <div class="char-screen">
      <div class="char-topbar">
        <button class="char-back-btn" id="char-back" type="button">‹ Back</button>
        <h2 class="char-title">Character</h2>
      </div>
      <div class="char-preview">
        <canvas id="char-canvas" width="${CANVAS_SIZE}" height="${CANVAS_SIZE}"></canvas>
      </div>
      <div class="char-options">
        <p class="char-options-label">Shirt Color</p>
        <div class="char-shirt-picker" id="char-shirt-picker">
          ${SHIRT_OPTIONS.map(s => buildShirtBtn(s, selected)).join('')}
        </div>
      </div>
    </div>
  `;

  document.getElementById('char-back').addEventListener('click', () => {
    _animGen++;
    goHome();
  });

  document.getElementById('char-shirt-picker').addEventListener('click', e => {
    const btn = e.target.closest('[data-shirt]');
    if (!btn) return;
    const id = btn.dataset.shirt;
    localStorage.setItem(SHIRT_KEY, id);
    document.querySelectorAll('.char-shirt-btn').forEach(b =>
      b.classList.toggle('selected', b.dataset.shirt === id)
    );
    const canvas = document.getElementById('char-canvas');
    if (canvas) startAnimation(canvas, id);
  });

  startAnimation(document.getElementById('char-canvas'), selected);
}

function buildShirtBtn(shirt, selected) {
  const isSelected = shirt.id === selected;
  const inner = shirt.src
    ? `<img src="${shirt.src}" alt="${shirt.label}" class="char-shirt-img">`
    : `<span class="char-shirt-swatch"></span>`;
  return `
    <button class="char-shirt-btn${isSelected ? ' selected' : ''}" data-shirt="${shirt.id}" type="button">
      ${inner}
      <span class="char-shirt-label">${shirt.label}</span>
    </button>
  `;
}

async function startAnimation(canvas, shirtId) {
  const gen = ++_animGen;
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = false;

  const sheet = await getSheet(shirtId);
  if (gen !== _animGen) return;

  let frame = 0;
  let lastTime = 0;
  const interval = 1000 / FPS;

  function draw(ts) {
    if (gen !== _animGen) return;
    if (ts - lastTime >= interval) {
      ctx.clearRect(0, 0, CANVAS_SIZE, CANVAS_SIZE);
      ctx.drawImage(sheet, frame * FRAME_W, 0, FRAME_W, FRAME_H, 0, 0, CANVAS_SIZE, CANVAS_SIZE);
      frame = (frame + 1) % FRAME_COUNT;
      lastTime = ts;
    }
    requestAnimationFrame(draw);
  }
  requestAnimationFrame(draw);
}

async function getSheet(shirtId) {
  if (_sheetCache[shirtId]) return _sheetCache[shirtId];

  const img = await loadImage('assets/Sprites/Idle/idle spritesheet.png');

  const off = document.createElement('canvas');
  off.width = img.width;
  off.height = img.height;
  const octx = off.getContext('2d');
  octx.drawImage(img, 0, 0);

  const option = SHIRT_OPTIONS.find(s => s.id === shirtId);
  if (option.targetHue !== null) {
    const imgData = octx.getImageData(0, 0, off.width, off.height);
    recolorShirt(imgData.data, option.targetHue);
    octx.putImageData(imgData, 0, 0);
  }

  _sheetCache[shirtId] = off;
  return off;
}

function recolorShirt(data, targetHue) {
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 10) continue;
    const [h, s, l] = rgbToHsl(data[i], data[i + 1], data[i + 2]);
    // blue shirt pixels: hue ~185-255, decent saturation
    if (h >= 185 && h <= 255 && s > 0.3) {
      const [r, g, b] = hslToRgb(targetHue, s, l);
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
    }
  }
}

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h * 60, s, l];
}

function hslToRgb(h, s, l) {
  h /= 360;
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const t2rgb = (t) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [
    Math.round(t2rgb(h + 1 / 3) * 255),
    Math.round(t2rgb(h) * 255),
    Math.round(t2rgb(h - 1 / 3) * 255),
  ];
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}
