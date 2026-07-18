import type { Receipt } from '../types';
import {
  formatDate,
  formatMoney,
  lineTotal,
  subtotal,
  taxAmount,
  total,
} from './format';

/** Escapes text so it can be safely embedded in the generated HTML. */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Builds a printable HTML document for a receipt, sized for an 80mm thermal
 * roll. This is what gets handed to `expo-print`.
 */
export function receiptToHtml(receipt: Receipt): string {
  const { currency } = receipt;

  const itemsHtml = receipt.items
    .map(
      (item) => `
        <tr>
          <td class="name">
            ${escapeHtml(item.name)}
            <div class="qty">${item.quantity} &times; ${escapeHtml(
              formatMoney(item.unitPrice, currency),
            )}</div>
          </td>
          <td class="amount">${escapeHtml(
            formatMoney(lineTotal(item), currency),
          )}</td>
        </tr>`,
    )
    .join('');

  const phoneHtml = receipt.merchant.phone
    ? `<div class="center">${escapeHtml(receipt.merchant.phone)}</div>`
    : '';

  const cashierHtml = receipt.cashier
    ? `<div class="meta"><span>Cashier</span><span>${escapeHtml(
        receipt.cashier,
      )}</span></div>`
    : '';

  return `<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      @page { margin: 0; }
      * { box-sizing: border-box; }
      body {
        font-family: 'Courier New', Courier, monospace;
        color: #000;
        margin: 0;
        padding: 16px;
        width: 302px; /* ~80mm at 96dpi */
      }
      .center { text-align: center; }
      .merchant { font-size: 18px; font-weight: 700; text-align: center; margin-bottom: 4px; }
      .sub { font-size: 12px; text-align: center; }
      hr { border: none; border-top: 1px dashed #999; margin: 12px 0; }
      .meta { display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 2px; }
      .meta span:first-child { color: #555; }
      table { width: 100%; border-collapse: collapse; }
      td { font-size: 13px; padding: 4px 0; vertical-align: top; }
      td.name { text-align: left; }
      td.amount { text-align: right; white-space: nowrap; }
      .qty { font-size: 11px; color: #777; }
      .summary { display: flex; justify-content: space-between; font-size: 13px; margin-top: 4px; }
      .total { font-weight: 700; font-size: 16px; }
      .thanks { text-align: center; font-size: 12px; margin-top: 4px; }
    </style>
  </head>
  <body>
    <div class="merchant">${escapeHtml(receipt.merchant.name)}</div>
    <div class="sub">${escapeHtml(receipt.merchant.address)}</div>
    ${phoneHtml}

    <hr />

    <div class="meta"><span>Receipt</span><span>#${escapeHtml(receipt.id)}</span></div>
    <div class="meta"><span>Date</span><span>${escapeHtml(
      formatDate(receipt.issuedAt),
    )}</span></div>
    ${cashierHtml}

    <hr />

    <table>${itemsHtml}</table>

    <hr />

    <div class="summary"><span>Subtotal</span><span>${escapeHtml(
      formatMoney(subtotal(receipt), currency),
    )}</span></div>
    <div class="summary"><span>Tax (${(receipt.taxRate * 100).toFixed(
      0,
    )}%)</span><span>${escapeHtml(
      formatMoney(taxAmount(receipt), currency),
    )}</span></div>
    <div class="summary total"><span>Total</span><span>${escapeHtml(
      formatMoney(total(receipt), currency),
    )}</span></div>

    <hr />

    <div class="thanks">Thank you for your purchase!</div>
  </body>
</html>`;
}
