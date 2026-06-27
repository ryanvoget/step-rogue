import { navigate, goHome } from '../nav.js';
import { getBank, addSteps } from './step-bank.js';
import { isHealthAvailable, requestHealthPermission, getTodaySteps } from './health.js';

export function handleSyncSteps() {
  navigate(renderSyncStepsScreen);
}

function renderSyncStepsScreen(container) {
  container.innerHTML = buildHTML(getBank());
  bindEvents(container);
  tryAutoFill(container);
}

async function tryAutoFill(container) {
  const available = await isHealthAvailable();
  if (!available) return;

  const healthBtn = container.querySelector('#btn-health-sync');
  if (healthBtn) healthBtn.classList.remove('hidden');

  const hint = container.querySelector('.input-hint');
  if (hint) hint.textContent = 'Steps auto-filled from Apple Health — adjust if needed.';

  const granted = await requestHealthPermission();
  if (!granted) {
    showFeedback(container, 'error', 'Health permission denied. Enter steps manually.');
    return;
  }

  const steps = await getTodaySteps();
  if (steps !== null) {
    const input = container.querySelector('#steps-input');
    if (input) input.value = steps;
    showFeedback(container, 'info', `Read ${steps.toLocaleString()} steps from Apple Health today.`);
  }
}

function buildHTML(bank) {
  const lastSync = bank.syncs[0] ? formatDate(bank.syncs[0].date) : 'Never';
  return `
    <div class="sync-screen">
      <header class="sync-header">
        <button class="back-btn" id="btn-back" type="button" aria-label="Back to menu">
          <span aria-hidden="true">‹</span> Back
        </button>
        <h1 class="sync-title">Sync Steps</h1>
      </header>

      <div class="bank-card">
        <p class="bank-label">Step Bank</p>
        <p class="bank-total" id="bank-total">${bank.total.toLocaleString()}</p>
        <p class="bank-meta" id="bank-meta">Last sync: ${lastSync}</p>
      </div>

      <div class="sync-form">
        <label class="input-label" for="steps-input">Today's step count</label>
        <input
          id="steps-input"
          class="steps-input"
          type="number"
          inputmode="numeric"
          placeholder="0"
          min="0"
          max="100000"
        >
        <p class="input-hint">Open your phone's Health app and enter your step total here.</p>
      </div>

      <button class="sync-btn hidden" id="btn-health-sync" type="button">
        <span aria-hidden="true">♻️</span>
        Re-read from Apple Health
      </button>

      <button class="sync-btn" id="btn-sync" type="button">
        <span aria-hidden="true">👟</span>
        Sync Steps to Bank
      </button>

      <div id="sync-feedback" class="sync-feedback" aria-live="polite"></div>
    </div>
  `;
}

function bindEvents(container) {
  container.querySelector('#btn-back').addEventListener('click', goHome);

  container.querySelector('#btn-sync').addEventListener('click', () => {
    const input = container.querySelector('#steps-input');
    const steps = parseInt(input.value, 10);

    if (!steps || steps <= 0) {
      showFeedback(container, 'error', 'Please enter a valid step count.');
      return;
    }

    const bank = addSteps(steps);
    input.value = '';
    container.querySelector('#bank-total').textContent = bank.total.toLocaleString();
    container.querySelector('#bank-meta').textContent = 'Last sync: Just now';
    showFeedback(container, 'success', `+${steps.toLocaleString()} steps deposited!`);
  });

  container.querySelector('#btn-health-sync')?.addEventListener('click', async () => {
    showFeedback(container, 'info', 'Reading from Apple Health…');
    const steps = await getTodaySteps();
    if (steps !== null) {
      container.querySelector('#steps-input').value = steps;
      showFeedback(container, 'info', `Read ${steps.toLocaleString()} steps from Apple Health today.`);
    } else {
      showFeedback(container, 'error', 'Could not read Health data. Try again.');
    }
  });
}

function showFeedback(container, type, message) {
  const el = container.querySelector('#sync-feedback');
  el.className = `sync-feedback sync-feedback--${type}`;
  el.textContent = message;
}

function formatDate(iso) {
  const d = new Date(iso);
  return d.toDateString() === new Date().toDateString()
    ? 'Today'
    : d.toLocaleDateString();
}
