export interface ReceiptItem {
  id: string;
  name: string;
  quantity: number;
  /** Unit price in the smallest currency unit (e.g. cents). */
  unitPrice: number;
}

export interface Receipt {
  id: string;
  merchant: {
    name: string;
    address: string;
    phone?: string;
  };
  /** ISO 8601 timestamp. */
  issuedAt: string;
  items: ReceiptItem[];
  /** Tax rate as a fraction, e.g. 0.08 for 8%. */
  taxRate: number;
  currency: string;
  cashier?: string;
}
