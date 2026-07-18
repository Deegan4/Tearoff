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
import { printReceipt, shareReceiptPdf } from './src/utils/print';

function reportError(action: string, error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  if (Platform.OS === 'web') {
    window.alert(`${action} failed: ${message}`);
  } else {
    Alert.alert(`${action} failed`, message);
  }
}

export default function App() {
  const [busy, setBusy] = useState<null | 'print' | 'pdf'>(null);

  const handlePrint = useCallback(async () => {
    if (busy) {
      return;
    }
    setBusy('print');
    try {
      await printReceipt(sampleReceipt);
    } catch (error) {
      reportError('Print', error);
    } finally {
      setBusy(null);
    }
  }, [busy]);

  const handleSavePdf = useCallback(async () => {
    if (busy) {
      return;
    }
    setBusy('pdf');
    try {
      await shareReceiptPdf(sampleReceipt);
    } catch (error) {
      reportError('Export', error);
    } finally {
      setBusy(null);
    }
  }, [busy]);

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
          <PressableScale
            style={[styles.button, styles.secondaryButton]}
            onPress={handleSavePdf}
          >
            <Ionicons name="document-text-outline" size={20} color="#f5f5f5" />
            <Text style={styles.secondaryButtonText}>
              {busy === 'pdf' ? 'Exporting…' : 'Save PDF'}
            </Text>
          </PressableScale>

          <PressableScale
            style={[styles.button, styles.primaryButton]}
            onPress={handlePrint}
          >
            <Ionicons name="print-outline" size={22} color="#111" />
            <Text style={styles.primaryButtonText}>
              {busy === 'print' ? 'Printing…' : 'Print receipt'}
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
    flexDirection: 'row',
    gap: 12,
    padding: 20,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#2a2a2a',
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 16,
    borderRadius: 14,
  },
  primaryButton: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  secondaryButton: {
    flex: 1,
    backgroundColor: '#2a2a2a',
  },
  primaryButtonText: {
    color: '#111',
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButtonText: {
    color: '#f5f5f5',
    fontSize: 16,
    fontWeight: '600',
  },
});
