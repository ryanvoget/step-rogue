import { navigate } from '../nav.js';
import { getInventory, removeItemsByIndices, addToInventory } from './inventory-store.js';
import { ITEMS } from './item-registry.js';

const RARITY_UP    = { common: 'uncommon', uncommon: 'rare', rare: 'epic' };
const ELIGIBLE     = new Set(['common', 'uncommon', 'rare']);
const REQUIRED     = 10;
const WINNER_INDEX = 42;
const CARD_WIDTH   = 110;
const CARD_GAP     = 8;
const CARD_SLOT    = CARD_WIDTH + CARD_GAP;

export function handleTradeUp() {
  navigate(renderSelectScreen);
}

// ── Selection screen ──────────────────────────────────────────────────────────

function renderSelectScreen(container) {
  const inventory = getInventory();
  const eligible = inventory
    .map((item, i) => ({ ...item, _invIdx: i }))
    .filter(item => ELIGIBLE.has(item.rarity));

  const selected = new Set();

  function getSelectedRarity() {
    for (const idx of selected) {
      const item = eligible.find(e => e._invIdx === idx);
      if (item) return item.rarity;
    }
    return null;
  }

  function syncFooter() {
    const count  = selected.size;
    const rarity = getSelectedRarity();
    const hint   = container.querySelector('#tradeup-hint');
    const btn    = container.querySelector('#btn-tradeup-confirm');
    if (!hint || !btn) return;
    hint.textContent = rarity
      ? `${count} / ${REQUIRED} ${rarity} selected`
      : 'Select 10 items of the same rarity';
    btn.disabled = count !== REQUIRED;
  }

  function syncCards() {
    const currentRarity = getSelectedRarity();
    container.querySelectorAll('.tradeup-card').forEach(card => {
      const invIdx     = parseInt(card.dataset.invIdx);
      const cardRarity = card.dataset.rarity;
      card.classList.toggle('tradeup-card--selected', selected.has(invIdx));
      card.classList.toggle('tradeup-card--locked',
        !!currentRarity && cardRarity !== currentRarity && !selected.has(invIdx));
    });
  }

  container.innerHTML = buildSelectHTML(eligible);
  syncFooter();

  container.querySelector('#btn-back').addEventListener('click', () => {
    import('./inventory.js').then(m => m.handleInventory());
  });

  container.querySelector('#btn-tradeup-confirm').addEventListener('click', () => {
    if (selected.size !== REQUIRED) return;
    const tradeRarity = getSelectedRarity();
    removeItemsByIndices([...selected]);
    const newRarity = RARITY_UP[tradeRarity];
    const pool = ITEMS.filter(i => i.rarity === newRarity);
    const won  = pool[Math.floor(Math.random() * pool.length)];
    navigate(c => renderSpinScreen(c, won, pool));
  });

  container.querySelectorAll('.tradeup-card').forEach(card => {
    card.addEventListener('click', () => {
      const invIdx     = parseInt(card.dataset.invIdx);
      const cardRarity = card.dataset.rarity;
      const current    = getSelectedRarity();
      if (current && cardRarity !== current) return;
      if (selected.has(invIdx)) {
        selected.delete(invIdx);
      } else if (selected.size < REQUIRED) {
        selected.add(invIdx);
      }
      syncCards();
      syncFooter();
    });
  });
}

function buildSelectHTML(eligible) {
  const sections = ['common', 'uncommon', 'rare']
    .filter(r => eligible.some(e => e.rarity === r))
    .map(rarity => {
      const cards = eligible
        .filter(e => e.rarity === rarity)
        .map(item => `
          <div class="tradeup-card tradeup-card--${item.rarity}"
               data-inv-idx="${item._invIdx}"
               data-rarity="${item.rarity}"
               title="${item.name}">
            <img src="assets/icons/${item.file}" alt="${item.name}">
          </div>
        `).join('');
      const label = rarity.charAt(0).toUpperCase() + rarity.slice(1);
      return `
        <div class="tradeup-section">
          <h3 class="tradeup-section-title tradeup-section-title--${rarity}">${label}</h3>
          <div class="tradeup-grid">${cards}</div>
        </div>
      `;
    }).join('');

  return `
    <div class="tradeup-screen">
      <header class="tradeup-header">
        <button class="back-btn" id="btn-back" type="button" aria-label="Back to inventory">
          <span aria-hidden="true">‹</span> Back
        </button>
        <h1 class="tradeup-title">Trade Up</h1>
      </header>
      <p class="tradeup-desc">Select 10 items of the same rarity to trade for a random item one tier higher.</p>
      <div class="tradeup-content">
        ${eligible.length > 0
          ? sections
          : '<p class="tradeup-empty">No eligible items. Open crates to collect common, uncommon, or rare items.</p>'
        }
      </div>
      <div class="tradeup-footer">
        <p class="tradeup-hint" id="tradeup-hint">Select 10 items of the same rarity</p>
        <button class="tradeup-confirm-btn" id="btn-tradeup-confirm" type="button" disabled>Trade Up →</button>
      </div>
    </div>
  `;
}

// ── Spin screen ───────────────────────────────────────────────────────────────

function renderSpinScreen(container, winner, pool) {
  const track = buildSpinTrack(winner, pool);
  container.innerHTML = buildSpinHTML(track);
  requestAnimationFrame(() => startSpin(container, winner));
}

function buildSpinTrack(winner, pool) {
  const rand  = () => pool[Math.floor(Math.random() * pool.length)];
  const track = [];
  for (let i = 0; i < WINNER_INDEX; i++) track.push(rand());
  track.push(winner);
  for (let i = 0; i < 8; i++) track.push(rand());
  return track;
}

function buildSpinHTML(track) {
  const cards = track.map(item => `
    <div class="spin-card spin-card--${item.rarity}">
      <img src="assets/icons/${item.file}" alt="${item.name}" width="110" height="110">
    </div>
  `).join('');

  return `
    <div class="crate-screen crate-screen--spin">
      <header class="crate-header">
        <h1 class="crate-title">Trading Up…</h1>
      </header>
      <div class="spin-stage">
        <div class="spin-viewport" id="spin-viewport">
          <div class="spin-track" id="spin-track">${cards}</div>
        </div>
        <div class="spin-line" aria-hidden="true"></div>
      </div>
      <p class="spin-hint">What will you get?</p>
    </div>
  `;
}

function startSpin(container, winner) {
  const track     = container.querySelector('#spin-track');
  const viewport  = container.querySelector('#spin-viewport');
  const viewportW = viewport.offsetWidth;

  const initialX = viewportW / 2 - CARD_SLOT / 2;
  const finalX   = viewportW / 2 - (WINNER_INDEX * CARD_SLOT + CARD_WIDTH / 2);

  track.style.transition = 'none';
  track.style.transform  = `translateX(${initialX}px)`;
  track.getBoundingClientRect();

  requestAnimationFrame(() => {
    track.style.transition = 'transform 5s cubic-bezier(0.12, 0, 0.08, 1)';
    track.style.transform  = `translateX(${finalX}px)`;
  });

  setTimeout(() => {
    addToInventory(winner);
    navigate(c => renderResultScreen(c, winner));
  }, 5400);
}

// ── Result screen ─────────────────────────────────────────────────────────────

function renderResultScreen(container, item) {
  const label = item.rarity.charAt(0).toUpperCase() + item.rarity.slice(1);
  container.innerHTML = `
    <div class="crate-screen crate-screen--result">
      <header class="crate-header">
        <h1 class="crate-title">Trade Up!</h1>
      </header>
      <div class="result-card result-card--${item.rarity}">
        <span class="result-rarity-label">${label}</span>
        <div class="result-item-frame result-item-frame--${item.rarity}">
          <img class="result-img" src="assets/icons/${item.file}" alt="${item.name}">
        </div>
        <h2 class="result-name">${item.name}</h2>
        <p class="result-saved">✓ Added to inventory</p>
      </div>
      <div class="result-actions">
        <button class="crate-buy-btn" id="btn-trade-again" type="button">⬆ Trade Up Again</button>
        <button class="result-home-btn" id="btn-go-inventory" type="button">Back to Inventory</button>
      </div>
    </div>
  `;

  container.querySelector('#btn-trade-again').addEventListener('click', handleTradeUp);
  container.querySelector('#btn-go-inventory').addEventListener('click', () => {
    import('./inventory.js').then(m => m.handleInventory());
  });
}
