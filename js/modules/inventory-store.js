const KEY = 'stepRogue_inventory';

export function getInventory() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) ?? [];
  } catch {
    return [];
  }
}

export function addToInventory(item) {
  const inv = getInventory();
  inv.unshift({ ...item, obtainedAt: new Date().toISOString() });
  localStorage.setItem(KEY, JSON.stringify(inv));
  return inv;
}

export function clearInventory() {
  localStorage.removeItem(KEY);
}

export function removeItemsByIndices(indices) {
  const inv = getInventory();
  const toRemove = new Set(indices);
  localStorage.setItem(KEY, JSON.stringify(inv.filter((_, i) => !toRemove.has(i))));
}
