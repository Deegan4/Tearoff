import {
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PressableScale } from 'pressto';

import type { Receipt } from '../types';
import type { ReceiptAction } from '../state/receiptReducer';
import { centsToInput, formatMoney, inputToCents, lineTotal } from '../utils/format';

interface ItemEditorProps {
  receipt: Receipt;
  dispatch: (action: ReceiptAction) => void;
}

/** Editable list of receipt line items: name, quantity, unit price, add/delete. */
export function ItemEditor({ receipt, dispatch }: ItemEditorProps) {
  const { currency } = receipt;

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Items</Text>

      {receipt.items.map((item) => (
        <View key={item.id} style={styles.itemCard}>
          <View style={styles.itemHeader}>
            <TextInput
              style={styles.nameInput}
              value={item.name}
              placeholder="Item name"
              placeholderTextColor="#777"
              onChangeText={(value) =>
                dispatch({ type: 'updateItem', id: item.id, field: 'name', value })
              }
            />
            <Pressable
              hitSlop={8}
              onPress={() => dispatch({ type: 'removeItem', id: item.id })}
              accessibilityLabel={`Remove ${item.name || 'item'}`}
            >
              <Ionicons name="trash-outline" size={20} color="#e57373" />
            </Pressable>
          </View>

          <View style={styles.fieldsRow}>
            <View style={styles.field}>
              <Text style={styles.fieldLabel}>Qty</Text>
              <TextInput
                style={styles.numberInput}
                value={String(item.quantity)}
                keyboardType="number-pad"
                onChangeText={(value) =>
                  dispatch({
                    type: 'updateItem',
                    id: item.id,
                    field: 'quantity',
                    value,
                  })
                }
              />
            </View>

            <View style={styles.field}>
              <Text style={styles.fieldLabel}>Unit price ({currency})</Text>
              <TextInput
                style={styles.numberInput}
                defaultValue={centsToInput(item.unitPrice)}
                keyboardType="decimal-pad"
                onEndEditing={(e) =>
                  dispatch({
                    type: 'updateItem',
                    id: item.id,
                    field: 'unitPrice',
                    value: inputToCents(e.nativeEvent.text),
                  })
                }
              />
            </View>

            <View style={styles.lineTotalWrap}>
              <Text style={styles.fieldLabel}>Total</Text>
              <Text style={styles.lineTotal}>
                {formatMoney(lineTotal(item), currency)}
              </Text>
            </View>
          </View>
        </View>
      ))}

      <PressableScale
        style={styles.addButton}
        onPress={() => dispatch({ type: 'addItem' })}
      >
        <Ionicons name="add" size={20} color="#f5f5f5" />
        <Text style={styles.addButtonText}>Add item</Text>
      </PressableScale>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
    maxWidth: 360,
    alignSelf: 'center',
    marginTop: 20,
  },
  heading: {
    color: '#f5f5f5',
    fontSize: 16,
    fontWeight: '700',
    marginBottom: 10,
  },
  itemCard: {
    backgroundColor: '#1c1c1c',
    borderRadius: 12,
    padding: 12,
    marginBottom: 10,
  },
  itemHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  nameInput: {
    flex: 1,
    color: '#f5f5f5',
    fontSize: 15,
    fontWeight: '600',
    paddingVertical: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#3a3a3a',
  },
  fieldsRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 12,
    marginTop: 10,
  },
  field: {
    flex: 1,
  },
  fieldLabel: {
    color: '#888',
    fontSize: 11,
    marginBottom: 4,
  },
  numberInput: {
    color: '#f5f5f5',
    fontSize: 15,
    backgroundColor: '#262626',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  lineTotalWrap: {
    flex: 1,
    alignItems: 'flex-end',
  },
  lineTotal: {
    color: '#f5f5f5',
    fontSize: 15,
    fontWeight: '600',
    paddingVertical: 8,
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    backgroundColor: '#2a2a2a',
    paddingVertical: 12,
    borderRadius: 12,
    marginTop: 2,
  },
  addButtonText: {
    color: '#f5f5f5',
    fontSize: 15,
    fontWeight: '600',
  },
});
