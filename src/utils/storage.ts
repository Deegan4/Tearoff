import AsyncStorage from '@react-native-async-storage/async-storage';

import type { Receipt } from '../types';

const STORAGE_KEY = 'iprint:receipt';

/** Loads the persisted receipt, or null if none has been saved yet. */
export async function loadReceipt(): Promise<Receipt | null> {
  try {
    const raw = await AsyncStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return null;
    }
    return JSON.parse(raw) as Receipt;
  } catch {
    // Corrupt or unreadable storage — fall back to the default receipt.
    return null;
  }
}

/** Persists the receipt. Failures are swallowed so editing never blocks. */
export async function saveReceipt(receipt: Receipt): Promise<void> {
  try {
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(receipt));
  } catch {
    // Best-effort persistence; ignore write errors.
  }
}
