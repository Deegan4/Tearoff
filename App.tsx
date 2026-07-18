import { useCallback, useState } from 'react';
import {
  Alert,
  Platform,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { StatusBar } from 'expo-status-bar';
import { PressableScale } from 'pressto';
import { Ionicons } from '@expo/vector-icons';

import { Receipt } from './src/components/Receipt';
import { sampleReceipt } from './src/data';
import { formatMoney, total } from './src/utils/format';

export default function App() {
  const [printing, setPrinting] = useState(false);

  const handlePrint = useCallback(() => {
    if (printing) {
      return;
    }
    setPrinting(true);

    // Simulate dispatching the receipt to a printer. Wiring up a real
    // printer (e.g. via a Bluetooth/ESC-POS module) can replace this.
    setTimeout(() => {
      setPrinting(false);
      const amount = formatMoney(total(sampleReceipt), sampleReceipt.currency);
      const message = `Receipt #${sampleReceipt.id} (${amount}) sent to printer.`;
      if (Platform.OS === 'web') {
        // Alert.alert is a no-op on web; fall back to the DOM dialog.
        window.alert(message);
      } else {
        Alert.alert('Printed', message);
      }
    }, 700);
  }, [printing]);

  return (
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaView style={styles.root}>
        <StatusBar style="light" />
        <View style={styles.header}>
          <Text style={styles.title}>iPrint</Text>
          <Text style={styles.subtitle}>Receipt preview</Text>
        </View>

        <ScrollView
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          <Receipt receipt={sampleReceipt} />
        </ScrollView>

        <View style={styles.footer}>
          <PressableScale style={styles.printButton} onPress={handlePrint}>
            <Ionicons name="print-outline" size={22} color="#111" />
            <Text style={styles.printButtonText}>
              {printing ? 'Printing…' : 'Print receipt'}
            </Text>
          </PressableScale>
        </View>
      </SafeAreaView>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#111111',
  },
  header: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 8,
  },
  title: {
    color: '#ffffff',
    fontSize: 28,
    fontWeight: '700',
  },
  subtitle: {
    color: '#9a9a9a',
    fontSize: 14,
    marginTop: 2,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  footer: {
    padding: 20,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#2a2a2a',
  },
  printButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    backgroundColor: '#f5f5f5',
    paddingVertical: 16,
    borderRadius: 14,
  },
  printButtonText: {
    color: '#111',
    fontSize: 16,
    fontWeight: '600',
  },
});
