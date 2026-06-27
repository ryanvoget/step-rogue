import { CapacitorHealthkit } from '@perfood/capacitor-healthkit';

const STEP_COUNT = 'stepCount';

function isNative() {
  return typeof window !== 'undefined' &&
    window.Capacitor?.isNativePlatform?.() === true;
}

export async function isHealthAvailable() {
  if (!isNative()) return false;
  try {
    const { available } = await CapacitorHealthkit.isAvailable();
    return !!available;
  } catch {
    return false;
  }
}

export async function requestHealthPermission() {
  try {
    await CapacitorHealthkit.requestAuthorization({
      read: [STEP_COUNT],
      write: [],
    });
    return true;
  } catch {
    return false;
  }
}

export async function getTodaySteps() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date();

  try {
    const result = await CapacitorHealthkit.queryHKitSampleType({
      sampleName: STEP_COUNT,
      startDate: start.toISOString(),
      endDate: end.toISOString(),
      limit: 0,
      ascending: false,
    });
    return result.resultData.reduce((sum, v) => sum + (v.value ?? 0), 0);
  } catch (err) {
    console.warn('[Health] query failed:', err);
    return null;
  }
}
