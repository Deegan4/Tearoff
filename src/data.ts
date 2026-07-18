import type { Receipt } from './types';

/** A sample receipt used to preview the print layout. */
export const sampleReceipt: Receipt = {
  id: 'R-1042',
  merchant: {
    name: 'iPrint Coffee Co.',
    address: '221B Baker Street, London',
    phone: '+44 20 7946 0958',
  },
  issuedAt: '2026-07-18T09:24:00.000Z',
  currency: 'USD',
  taxRate: 0.08,
  cashier: 'Mehdi',
  items: [
    { id: '1', name: 'Espresso', quantity: 2, unitPrice: 320 },
    { id: '2', name: 'Blueberry Muffin', quantity: 1, unitPrice: 450 },
    { id: '3', name: 'Cold Brew (Large)', quantity: 1, unitPrice: 520 },
    { id: '4', name: 'Oat Milk', quantity: 3, unitPrice: 75 },
  ],
};
