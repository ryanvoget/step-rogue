import { renderMenuScreen } from './menu.js';
import { initNav } from './nav.js';

async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register('/sw.js');
  } catch (err) {
    console.warn('[App] Service worker registration failed:', err);
  }
}

function init() {
  registerServiceWorker();
  const container = document.getElementById('screen-container');
  initNav(container, renderMenuScreen);
  renderMenuScreen(container);
}

init();
