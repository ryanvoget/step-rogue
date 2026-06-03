import { navigate, goHome } from '../nav.js';
import { getInventory, clearInventory } from './inventory-store.js';
import { handleTradeUp } from './trade-up.js';

const ASSET_PATH = 'assets/icons/';
const RARITY_ORDER = { legendary: 0, epic: 1, rare: 2, uncommon: 3, common: 4 };

export function handleInventory() {
  navigate(renderInventoryScreen);
}

function renderInventoryScreen(container) {
  const items = getInventory();
  container.innerHTML = buildHTML(items);
  container.querySelector('#btn-back').addEventListener('click', goHome);
  container.querySelector('#btn-trade-up')?.addEventListener('click', handleTradeUp);
  container.querySelector('#btn-clear-inventory')?.addEventListener('click', () => {
    clearInventory();
    navigate(renderInventoryScreen);
  });
}

function buildHTML(items) {
  if (items.length === 0) {
    return `
      <div class="inv-screen">
        <header class="inv-header">
          <button class="back-btn" id="btn-back" type="button" aria-label="Back to menu">
            <span aria-hidden="true">‹</span> Back
          </button>
          <h1 class="inv-title">Inventory</h1>
        </header>
        <div class="inv-empty">
          <span class="inv-empty-icon">🎒</span>
          <p class="inv-empty-msg">No items yet</p>
          <p class="inv-empty-sub">Open crates to find items</p>
        </div>
      </div>
    `;
  }

  const sorted = [...items].sort(
    (a, b) => (RARITY_ORDER[a.rarity] ?? 5) - (RARITY_ORDER[b.rarity] ?? 5)
  );

  const cards = sorted.map(item => `
    <div class="inv-card inv-card--${item.rarity}" title="${item.name}">
      <img src="${ASSET_PATH}${item.file}" alt="${item.name}" loading="lazy">
    </div>
  `).join('');

  return `
    <div class="inv-screen">
      <header class="inv-header">
        <button class="back-btn" id="btn-back" type="button" aria-label="Back to menu">
          <span aria-hidden="true">‹</span> Back
        </button>
        <h1 class="inv-title">Inventory</h1>
        <span class="inv-count">${items.length}</span>
      </header>
      <div class="inv-grid">${cards}</div>
      <div class="inv-actions-row">
        <button class="inv-trade-up-btn" id="btn-trade-up" type="button">⬆ Trade Up</button>
        <button class="inv-clear-btn" id="btn-clear-inventory" type="button">Clear Inventory</button>
      </div>
    </div>
  `;
}
