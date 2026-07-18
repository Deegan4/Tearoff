import { Platform } from 'react-native';
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';

import type { Receipt } from '../types';
import { receiptToHtml } from './receiptHtml';

/**
 * Sends a receipt to the OS print dialog via `expo-print`.
 *
 * - On iOS/Android this opens the native AirPrint / print sheet, where the
 *   user can pick a physical or PDF printer.
 * - On web it opens the browser print dialog.
 */
export async function printReceipt(receipt: Receipt): Promise<void> {
  const html = receiptToHtml(receipt);
  await Print.printAsync({ html });
}

/**
 * Renders a receipt to a PDF file and opens the share sheet so it can be
 * saved or sent. Returns the file URI.
 *
 * On web there is no share sheet, so this opens the generated PDF in a new
 * tab instead.
 */
export async function shareReceiptPdf(receipt: Receipt): Promise<string> {
  const html = receiptToHtml(receipt);
  const { uri } = await Print.printToFileAsync({ html });

  if (Platform.OS === 'web') {
    // expo-sharing is unavailable on web; open the PDF directly.
    if (typeof window !== 'undefined') {
      window.open(uri, '_blank');
    }
    return uri;
  }

  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(uri, {
      mimeType: 'application/pdf',
      dialogTitle: 'Share receipt',
      UTI: 'com.adobe.pdf',
    });
  }

  return uri;
}
