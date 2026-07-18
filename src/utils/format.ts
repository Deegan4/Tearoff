import type { Receipt, ReceiptItem } from '../types';

/** Formats an amount given in the smallest currency unit (cents) into a display string. */
export function formatMoney(amountInCents: number, currency: string): string {
  const value = amountInCents / 100;
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency,
    }).format(value);
  } catch {
    // Fall back to a plain fixed-decimal string if the currency code is unknown.
    return `${currency} ${value.toFixed(2)}`;
  }
}

export function lineTotal(item: ReceiptItem): number {
  return item.quantity * item.unitPrice;
}

export function subtotal(receipt: Receipt): number {
  return receipt.items.reduce((sum, item) => sum + lineTotal(item), 0);
}

export function taxAmount(receipt: Receipt): number {
  return Math.round(subtotal(receipt) * receipt.taxRate);
}

export function total(receipt: Receipt): number {
  return subtotal(receipt) + taxAmount(receipt);
}

/** Converts an amount in cents into a plain editable decimal string, e.g. 320 -> "3.20". */
export function centsToInput(amountInCents: number): string {
  return (amountInCents / 100).toFixed(2);
}

/** Parses a user-entered major-unit amount (e.g. "3.20") into cents. Returns 0 for invalid input. */
export function inputToCents(input: string): number {
  const value = Number(input.replace(/[^0-9.]/g, ''));
  if (!Number.isFinite(value) || value < 0) {
    return 0;
  }
  return Math.round(value * 100);
}

export function formatDate(isoString: string): string {
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) {
    return isoString;
  }
  return date.toLocaleString();
}
