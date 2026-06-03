import { navigate, goHome } from '../nav.js';
import { getBank, spendSteps } from './step-bank.js';
import { rollItem, randomItem } from './item-registry.js';
import { addToInventory } from './inventory-store.js';

const KEY_COST = 2000;
const ASSET_PATH = 'assets/icons/';
const WINNER_INDEX = 42;
const CARD_WIDTH = 110;
const CARD_GAP = 8;
const CARD_SLOT = CARD_WIDTH + CARD_GAP;

export function handleOpenCrate() {
  navigate(renderPurchaseScreen);
}

function renderPurchaseScreen(container) {
  const bank = getBank();
  container.innerHTML = buildPurchaseHTML(bank.total);
  container.querySelector('#btn-back').addEventListener('click', goHome);
  container.querySelector('#btn-buy-key')?.addEventListener('click', () => {
    const bank = spendSteps(KEY_COST);
    if (!bank) return;
    navigate(renderSpinScreen);
  });
}

function buildPurchaseHTML(steps) {
  const canAfford = steps >= KEY_COST;
  const shortfall = KEY_COST - steps;
  return `
    <div class="crate-screen">
      <header class="crate-header">
        <button class="back-btn" id="btn-back" type="button" aria-label="Back to menu">
          <span aria-hidden="true">‹</span> Back
        </button>
        <h1 class="crate-title">Open Crate</h1>
      </header>

      <div class="crate-key-card">
        <div class="crate-key-icon">📦</div>
        <h2 class="crate-key-name">Supply Crate</h2>
        <p class="crate-key-desc">Spend steps to unlock a random item</p>

        <div class="crate-cost-pill">
          <span>👟</span>
          <span class="crate-cost-num">2,000</span>
          <span class="crate-cost-unit">steps per key</span>
        </div>

        <p class="crate-balance">
          Balance: <strong>${steps.toLocaleString()}</strong> steps
        </p>

        <button class="crate-buy-btn" id="btn-buy-key" type="button" ${canAfford ? '' : 'disabled'}>
          ${canAfford ? '🔑 Buy Key &amp; Open' : 'Not enough steps'}
        </button>

        ${!canAfford ? `<p class="crate-shortfall">Need ${shortfall.toLocaleString()} more steps</p>` : ''}
      </div>

      <div class="crate-odds-card">
        <h3 class="crate-odds-title">Drop Rates</h3>
        <ul class="crate-odds-list">
          <li><span class="odds-label odds--common">Common</span><span class="odds-pct">55%</span></li>
          <li><span class="odds-label odds--uncommon">Uncommon</span><span class="odds-pct">30%</span></li>
          <li><span class="odds-label odds--rare">Rare</span><span class="odds-pct">10%</span></li>
          <li><span class="odds-label odds--epic">Epic</span><span class="odds-pct">4%</span></li>
          <li><span class="odds-label odds--legendary">Legendary</span><span class="odds-pct">1%</span></li>
        </ul>
      </div>
    </div>
  `;
}

function buildTrack(winner) {
  const track = [];
  for (let i = 0; i < WINNER_INDEX; i++) track.push(randomItem());
  track.push(winner);
  for (let i = 0; i < 8; i++) track.push(randomItem());
  return track;
}

function renderSpinScreen(container) {
  const winner = rollItem();
  const track = buildTrack(winner);

  container.innerHTML = buildSpinHTML(track);

  requestAnimationFrame(() => startSpin(container, winner));
}

function buildSpinHTML(track) {
  const cards = track.map(item => `
    <div class="spin-card spin-card--${item.rarity}">
      <img src="${ASSET_PATH}${item.file}" alt="${item.name}" width="110" height="110">
    </div>
  `).join('');

  return `
    <div class="crate-screen crate-screen--spin">
      <header class="crate-header">
        <h1 class="crate-title">Opening Crate…</h1>
      </header>

      <div class="spin-stage">
        <div class="spin-viewport" id="spin-viewport">
          <div class="spin-track" id="spin-track">${cards}</div>
        </div>
        <div class="spin-line" aria-hidden="true"></div>
      </div>

      <p class="spin-hint">Good luck…</p>
    </div>
  `;
}

function startSpin(container, winner) {
  const track = container.querySelector('#spin-track');
  const viewport = container.querySelector('#spin-viewport');
  const viewportW = viewport.offsetWidth;

  const initialX = viewportW / 2 - CARD_SLOT / 2;
  const finalX = viewportW / 2 - (WINNER_INDEX * CARD_SLOT + CARD_WIDTH / 2);

  track.style.transition = 'none';
  track.style.transform = `translateX(${initialX}px)`;
  track.getBoundingClientRect();

  requestAnimationFrame(() => {
    track.style.transition = 'transform 5s cubic-bezier(0.12, 0, 0.08, 1)';
    track.style.transform = `translateX(${finalX}px)`;
  });

  setTimeout(() => {
    addToInventory(winner);
    navigate(c => renderResultScreen(c, winner));
  }, 5400);
}

function renderResultScreen(container, winner) {
  const label = winner.rarity.charAt(0).toUpperCase() + winner.rarity.slice(1);
  container.innerHTML = `
    <div class="crate-screen crate-screen--result">
      <header class="crate-header">
        <h1 class="crate-title">You got…</h1>
      </header>

      <div class="result-card result-card--${winner.rarity}">
        <span class="result-rarity-label">${label}</span>
        <div class="result-item-frame result-item-frame--${winner.rarity}">
          <img class="result-img" src="${ASSET_PATH}${winner.file}" alt="${winner.name}">
        </div>
        <h2 class="result-name">${winner.name}</h2>
        <p class="result-saved">✓ Added to inventory</p>
      </div>

      <div class="result-actions">
        <button class="crate-buy-btn" id="btn-open-another" type="button">🔑 Open Another</button>
        <button class="result-home-btn" id="btn-go-home" type="button">Back to Menu</button>
      </div>
    </div>
  `;

  container.querySelector('#btn-open-another').addEventListener('click', () => navigate(renderPurchaseScreen));
  container.querySelector('#btn-go-home').addEventListener('click', goHome);
}
