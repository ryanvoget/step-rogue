const BANK_KEY = 'stepRogue_stepBank';

function load() {
  try {
    return JSON.parse(localStorage.getItem(BANK_KEY)) ?? { total: 0, syncs: [] };
  } catch {
    return { total: 0, syncs: [] };
  }
}

function save(data) {
  localStorage.setItem(BANK_KEY, JSON.stringify(data));
}

export function getBank() {
  return load();
}

export function addSteps(steps) {
  const bank = load();
  bank.total += steps;
  bank.syncs.unshift({ steps, date: new Date().toISOString() });
  if (bank.syncs.length > 10) bank.syncs.length = 10;
  save(bank);
  return bank;
}

export function spendSteps(amount) {
  const bank = load();
  if (bank.total < amount) return null;
  bank.total -= amount;
  save(bank);
  return bank;
}
