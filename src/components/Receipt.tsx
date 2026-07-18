import { StyleSheet, Text, View } from 'react-native';

import type { Receipt as ReceiptModel } from '../types';
import {
  formatDate,
  formatMoney,
  lineTotal,
  subtotal,
  taxAmount,
  total,
} from '../utils/format';

interface ReceiptProps {
  receipt: ReceiptModel;
}

/** Renders a thermal-printer style receipt preview. */
export function Receipt({ receipt }: ReceiptProps) {
  const { currency } = receipt;

  return (
    <View style={styles.paper}>
      <Text style={styles.merchantName}>{receipt.merchant.name}</Text>
      <Text style={styles.centered}>{receipt.merchant.address}</Text>
      {receipt.merchant.phone ? (
        <Text style={styles.centered}>{receipt.merchant.phone}</Text>
      ) : null}

      <Divider />

      <View style={styles.metaRow}>
        <Text style={styles.metaLabel}>Receipt</Text>
        <Text style={styles.metaValue}>#{receipt.id}</Text>
      </View>
      <View style={styles.metaRow}>
        <Text style={styles.metaLabel}>Date</Text>
        <Text style={styles.metaValue}>{formatDate(receipt.issuedAt)}</Text>
      </View>
      {receipt.cashier ? (
        <View style={styles.metaRow}>
          <Text style={styles.metaLabel}>Cashier</Text>
          <Text style={styles.metaValue}>{receipt.cashier}</Text>
        </View>
      ) : null}

      <Divider />

      {receipt.items.map((item) => (
        <View key={item.id} style={styles.itemRow}>
          <View style={styles.itemInfo}>
            <Text style={styles.itemName}>{item.name}</Text>
            <Text style={styles.itemQty}>
              {item.quantity} × {formatMoney(item.unitPrice, currency)}
            </Text>
          </View>
          <Text style={styles.itemTotal}>
            {formatMoney(lineTotal(item), currency)}
          </Text>
        </View>
      ))}

      <Divider />

      <SummaryRow
        label="Subtotal"
        value={formatMoney(subtotal(receipt), currency)}
      />
      <SummaryRow
        label={`Tax (${(receipt.taxRate * 100).toFixed(0)}%)`}
        value={formatMoney(taxAmount(receipt), currency)}
      />
      <SummaryRow
        label="Total"
        value={formatMoney(total(receipt), currency)}
        emphasized
      />

      <Divider />

      <Text style={styles.thankYou}>Thank you for your purchase!</Text>
    </View>
  );
}

function Divider() {
  return <View style={styles.divider} />;
}

function SummaryRow({
  label,
  value,
  emphasized,
}: {
  label: string;
  value: string;
  emphasized?: boolean;
}) {
  return (
    <View style={styles.summaryRow}>
      <Text style={[styles.summaryLabel, emphasized && styles.emphasized]}>
        {label}
      </Text>
      <Text style={[styles.summaryValue, emphasized && styles.emphasized]}>
        {value}
      </Text>
    </View>
  );
}

const mono = 'Courier';

const styles = StyleSheet.create({
  paper: {
    backgroundColor: '#ffffff',
    padding: 20,
    borderRadius: 8,
    width: '100%',
    maxWidth: 360,
    alignSelf: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.15,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
  },
  merchantName: {
    fontFamily: mono,
    fontSize: 18,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 4,
    color: '#111',
  },
  centered: {
    fontFamily: mono,
    fontSize: 12,
    textAlign: 'center',
    color: '#333',
  },
  divider: {
    borderBottomWidth: 1,
    borderStyle: 'dashed',
    borderColor: '#bbb',
    marginVertical: 12,
  },
  metaRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 2,
  },
  metaLabel: {
    fontFamily: mono,
    fontSize: 12,
    color: '#666',
  },
  metaValue: {
    fontFamily: mono,
    fontSize: 12,
    color: '#111',
  },
  itemRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  itemInfo: {
    flex: 1,
    paddingRight: 8,
  },
  itemName: {
    fontFamily: mono,
    fontSize: 14,
    color: '#111',
  },
  itemQty: {
    fontFamily: mono,
    fontSize: 11,
    color: '#777',
  },
  itemTotal: {
    fontFamily: mono,
    fontSize: 14,
    color: '#111',
  },
  summaryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  summaryLabel: {
    fontFamily: mono,
    fontSize: 13,
    color: '#333',
  },
  summaryValue: {
    fontFamily: mono,
    fontSize: 13,
    color: '#111',
  },
  emphasized: {
    fontWeight: '700',
    fontSize: 16,
  },
  thankYou: {
    fontFamily: mono,
    fontSize: 12,
    textAlign: 'center',
    color: '#333',
  },
});
