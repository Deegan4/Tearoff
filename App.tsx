import { useCallback, useEffect, useReducer, useRef, useState } from 'react';
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
import { ItemEditor } from './src/components/ItemEditor';
import { PrinterOverlay } from './src/components/PrinterOverlay';
import { sampleReceipt } from './src/data';
import { receiptReducer } from './src/state/receiptReducer';
import { printReceipt, shareReceiptPdf } from './src/utils/print';
import { loadReceipt, saveReceipt } from './src/utils/storage';

function reportError(action: string, error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  if (Platform.OS === 'web') {
    window.alert(`${action} failed: ${message}`);
  } else {
    Alert.alert(`${action} failed`, message);
  }
}

export default function App() {
  const [receipt, dispatch] = useReducer(receiptReducer, sampleReceipt);
  const [editing, setEditing] = useState(false);
  const [printing, setPrinting] = useState(false);
  const [busy, setBusy] = useState<null | 'print' | 'pdf'>(null);
  const hydratedRef = useRef(false);

  // Load any persisted receipt on first mount.
  useEffect(() => {
    let active = true;
    loadReceipt().then((saved) => {
      if (active && saved) {
        dispatch({ type: 'reset', receipt: saved });
      }
      if (active) {
        hydratedRef.current = true;
      }
    });
    return () => {
      active = false;
    };
  }, []);

  // Persist on every change, but only after the initial load so we don't
  // clobber stored data with the default before it has been read.
  useEffect(() => {
    if (hydratedRef.current) {
      saveReceipt(receipt);
    }
  }, [receipt]);

  const runOutput = useCallback(
    async (kind: 'print' | 'pdf') => {
      if (busy) {
        return;
      }
      setBusy(kind);
      try {
        if (kind === 'print') {
          await printReceipt(receipt);
        } else {
          await shareReceiptPdf(receipt);
        }
      } catch (error) {
        reportError(kind === 'print' ? 'Print' : 'Export', error);
      } finally {
        setBusy(null);
      }
    },
    [busy, receipt],
  );

  return (
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaView style={styles.root}>
        <StatusBar style="light" />
        <View style={styles.header}>
          <View>
            <Text style={styles.title}>iPrint</Text>
            <Text style={styles.subtitle}>
              {editing ? 'Edit items' : 'Receipt preview'}
            </Text>
          </View>
          <PressableScale
            style={styles.editToggle}
            onPress={() => setEditing((v) => !v)}
          >
            <Ionicons
              name={editing ? 'checkmark' : 'create-outline'}
              size={18}
              color="#111"
            />
            <Text style={styles.editToggleText}>
              {editing ? 'Done' : 'Edit'}
            </Text>
          </PressableScale>
        </View>

        <ScrollView
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        >
          {editing ? (
            <ItemEditor receipt={receipt} dispatch={dispatch} />
          ) : (
            <Receipt receipt={receipt} />
          )}
        </ScrollView>

        {!editing && (
          <View style={styles.footer}>
            <PressableScale
              style={[styles.button, styles.secondaryButton]}
              onPress={() => runOutput('pdf')}
            >
              <Ionicons name="document-text-outline" size={20} color="#f5f5f5" />
              <Text style={styles.secondaryButtonText}>
                {busy === 'pdf' ? 'Exporting…' : 'Save PDF'}
              </Text>
            </PressableScale>

            <PressableScale
              style={[styles.button, styles.primaryButton]}
              onPress={() => setPrinting(true)}
            >
              <Ionicons name="print-outline" size={22} color="#111" />
              <Text style={styles.primaryButtonText}>Print receipt</Text>
            </PressableScale>
          </View>
        )}

        <PrinterOverlay
          visible={printing}
          receipt={receipt}
          onClose={() => setPrinting(false)}
          onPrintForReal={() => runOutput('print')}
        />
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
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
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
  editToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: '#f5f5f5',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
  },
  editToggleText: {
    color: '#111',
    fontSize: 14,
    fontWeight: '600',
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
