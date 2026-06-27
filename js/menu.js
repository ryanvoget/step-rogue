import { handleSyncSteps } from './modules/sync-steps.js';
import { handleOpenCrate } from './modules/open-crate.js';
import { handleSettings } from './modules/settings.js';
import { handlePlay } from './modules/play.js';
import { handleInventory } from './modules/inventory.js';
import { handleCharacter } from './modules/character.js';
import { initAudio } from './modules/audio.js';

const MENU_BUTTONS = [
  {
    id: 'btn-play',
    label: 'Play',
    icon: '⚔️',
    variant: 'play',
    handler: handlePlay,
  },
  {
    id: 'btn-sync-steps',
    label: 'Sync Steps',
    icon: '👟',
    variant: 'secondary',
    handler: handleSyncSteps,
  },
  {
    id: 'btn-open-crate',
    label: 'Open Crate',
    icon: '📦',
    variant: 'secondary',
    handler: handleOpenCrate,
  },
  {
    id: 'btn-inventory',
    label: 'Inventory',
    icon: '🎒',
    variant: 'secondary',
    handler: handleInventory,
  },
  {
    id: 'btn-character',
    label: 'Character',
    icon: '🧑',
    variant: 'secondary',
    handler: handleCharacter,
  },
  {
    id: 'btn-settings',
    label: 'Settings',
    icon: '⚙️',
    variant: 'secondary',
    handler: handleSettings,
  },
];

export function renderMenuScreen(container) {
  initAudio();
  container.innerHTML = buildMenuHTML();
  bindMenuEvents(container);
}

function buildMenuHTML() {
  const buttonsHTML = MENU_BUTTONS.map(buildButtonHTML).join('');
  return `
    <div class="menu-screen">
      <header class="menu-header">
        <div class="menu-logo">
          <img src="assets/icons/icon.svg" alt="Parsec logo" width="48" height="48">
        </div>
        <h1 class="menu-title">Parsec</h1>
        <p class="menu-subtitle">Walk to adventure</p>
      </header>
      <nav aria-label="Main menu">
        <ul class="menu-buttons">
          ${buttonsHTML}
        </ul>
      </nav>
      <footer class="menu-footer">v0.1.0</footer>
    </div>
  `;
}

function buildButtonHTML({ id, label, icon, variant }) {
  return `
    <li>
      <button id="${id}" class="menu-btn menu-btn--${variant}" type="button">
        <span class="btn-icon" aria-hidden="true">${icon}</span>
        <span class="btn-label">${label}</span>
        <span class="btn-arrow" aria-hidden="true">›</span>
      </button>
    </li>
  `;
}

function bindMenuEvents(container) {
  for (const { id, handler } of MENU_BUTTONS) {
    container.querySelector(`#${id}`)?.addEventListener('click', handler);
  }
}
