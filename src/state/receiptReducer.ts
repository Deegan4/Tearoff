import type { Receipt, ReceiptItem } from '../types';

export type EditableItemField = 'name' | 'quantity' | 'unitPrice';

export type ReceiptAction =
  | { type: 'reset'; receipt: Receipt }
  | { type: 'addItem' }
  | { type: 'removeItem'; id: string }
  | {
      type: 'updateItem';
      id: string;
      field: EditableItemField;
      value: string | number;
    };

let itemCounter = 0;

/** Generates a stable-enough unique id for a new line item. */
function nextItemId(): string {
  itemCounter += 1;
  return `item-${itemCounter}-${itemCounter * 2654435761}`;
}

function emptyItem(): ReceiptItem {
  return { id: nextItemId(), name: '', quantity: 1, unitPrice: 0 };
}

function updateItemField(
  item: ReceiptItem,
  field: EditableItemField,
  value: string | number,
): ReceiptItem {
  switch (field) {
    case 'name':
      return { ...item, name: String(value) };
    case 'quantity': {
      const n = Math.max(0, Math.round(Number(value) || 0));
      return { ...item, quantity: n };
    }
    case 'unitPrice': {
      const n = Math.max(0, Math.round(Number(value) || 0));
      return { ...item, unitPrice: n };
    }
    default:
      return item;
  }
}

export function receiptReducer(
  state: Receipt,
  action: ReceiptAction,
): Receipt {
  switch (action.type) {
    case 'reset':
      return action.receipt;

    case 'addItem':
      return { ...state, items: [...state.items, emptyItem()] };

    case 'removeItem':
      return {
        ...state,
        items: state.items.filter((item) => item.id !== action.id),
      };

    case 'updateItem':
      return {
        ...state,
        items: state.items.map((item) =>
          item.id === action.id
            ? updateItemField(item, action.field, action.value)
            : item,
        ),
      };

    default:
      return state;
  }
}
