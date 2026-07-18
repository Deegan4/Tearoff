import { useEffect, useState } from 'react';
import {
  Modal,
  Platform,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import Animated, {
  Easing,
  interpolate,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withRepeat,
  withSequence,
  withTiming,
} from 'react-native-reanimated';
import Svg, { Polygon } from 'react-native-svg';
import { PressableScale } from 'pressto';
import { Ionicons } from '@expo/vector-icons';

import type { Receipt as ReceiptModel } from '../types';
import { Receipt } from './Receipt';

const PAPER_WIDTH = 320;
const BEZEL_HEIGHT = 96;
const TEETH = 22;
const TOOTH_H = 12;

interface PrinterOverlayProps {
  visible: boolean;
  receipt: ReceiptModel;
  onClose: () => void;
  onPrintForReal: () => void;
}

/** Mechanical feed easing — advances in discrete steps like a thermal printer. */
function feedEasing(t: number) {
  'worklet';
  const steps = 16;
  return Math.min(1, Math.floor(t * steps + 0.0001) / steps);
}

/** A zigzag torn edge for the hanging end of the paper. */
function TornEdge() {
  const points: string[] = [];
  const step = PAPER_WIDTH / TEETH;
  for (let i = 0; i <= TEETH; i += 1) {
    const x = i * step;
    points.push(`${x},0`);
    points.push(`${x + step / 2},${TOOTH_H}`);
  }
  points.push(`${PAPER_WIDTH},0`);
  return (
    <Svg width={PAPER_WIDTH} height={TOOTH_H} style={styles.tornEdge}>
      <Polygon points={points.join(' ')} fill="#ffffff" />
    </Svg>
  );
}

export function PrinterOverlay({
  visible,
  receipt,
  onClose,
  onPrintForReal,
}: PrinterOverlayProps) {
  const { height: screenHeight } = useWindowDimensions();
  const [phase, setPhase] = useState<'feeding' | 'done'>('feeding');
  const [paperHeight, setPaperHeight] = useState(0);

  const backdrop = useSharedValue(0);
  const feed = useSharedValue(0);
  const paperH = useSharedValue(0);
  const jitter = useSharedValue(0);
  const led = useSharedValue(0);
  const scan = useSharedValue(0);
  const tear = useSharedValue(0);

  // Reset and run the print sequence whenever the overlay opens with a
  // measured paper height.
  useEffect(() => {
    if (!visible || paperHeight === 0) {
      return;
    }
    setPhase('feeding');
    paperH.value = paperHeight + TOOTH_H;
    feed.value = 0;
    tear.value = 0;
    backdrop.value = withTiming(1, { duration: 240 });
    led.value = withRepeat(
      withSequence(
        withTiming(1, { duration: 90 }),
        withTiming(0.25, { duration: 420 }),
      ),
      -1,
    );
    scan.value = withRepeat(withTiming(1, { duration: 900 }), -1, false);
    jitter.value = withRepeat(
      withSequence(
        withTiming(1, { duration: 55 }),
        withTiming(-1, { duration: 55 }),
      ),
      -1,
      true,
    );
    feed.value = withDelay(
      380,
      withTiming(1, { duration: 2600, easing: feedEasing }, (finished) => {
        if (finished) {
          jitter.value = 0;
          runOnJS(setPhase)('done');
        }
      }),
    );
  }, [visible, paperHeight, backdrop, feed, paperH, jitter, led, scan, tear]);

  const backdropStyle = useAnimatedStyle(() => ({ opacity: backdrop.value }));

  const paperStyle = useAnimatedStyle(() => {
    const y = -paperH.value * (1 - feed.value) + tear.value * screenHeight;
    const wobble = feed.value < 1 ? jitter.value * 0.6 : 0;
    return {
      transform: [{ translateY: y }, { translateX: wobble }],
      opacity: interpolate(tear.value, [0, 0.9, 1], [1, 1, 0]),
    };
  });

  const ledStyle = useAnimatedStyle(() => ({ opacity: 0.25 + led.value * 0.75 }));

  const scanStyle = useAnimatedStyle(() => ({
    opacity: interpolate(scan.value, [0, 0.5, 1], [0, 0.9, 0]),
    transform: [
      { translateX: interpolate(scan.value, [0, 1], [-PAPER_WIDTH / 2, PAPER_WIDTH / 2]) },
    ],
  }));

  const controlsStyle = useAnimatedStyle(() => ({
    opacity: phase === 'done' ? withTiming(1, { duration: 260 }) : 0,
    transform: [
      { translateY: phase === 'done' ? withTiming(0, { duration: 260 }) : 24 },
    ],
  }));

  const handleTearOff = () => {
    tear.value = withTiming(1, { duration: 460, easing: Easing.in(Easing.cubic) }, (finished) => {
      if (finished) {
        runOnJS(onClose)();
      }
    });
    backdrop.value = withDelay(160, withTiming(0, { duration: 300 }));
  };

  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={onClose}>
      <Animated.View style={[styles.backdrop, backdropStyle]}>
        {/* Feed window: paper emerges from here, clipped at the slot line. */}
        <View style={styles.feedWindow} pointerEvents="box-none">
          <Animated.View style={[styles.paperWrap, paperStyle]}>
            <View
              style={styles.paper}
              onLayout={(e) => setPaperHeight(e.nativeEvent.layout.height)}
            >
              <Receipt receipt={receipt} />
            </View>
            <TornEdge />
          </Animated.View>
        </View>

        {/* Printer bezel with the slot the paper feeds through. */}
        <View style={styles.bezel} pointerEvents="box-none">
          <View style={styles.bezelTopRow}>
            <View style={styles.brandRow}>
              <Ionicons name="print" size={18} color="#c8c8c8" />
              <Text style={styles.brand}>iPrint</Text>
            </View>
            <View style={styles.ledRow}>
              <Animated.View style={[styles.led, ledStyle]} />
              <Text style={styles.ledLabel}>
                {phase === 'done' ? 'READY' : 'PRINTING'}
              </Text>
            </View>
          </View>

          <View style={styles.grille}>
            <View style={styles.grilleLine} />
            <View style={styles.grilleLine} />
            <View style={styles.grilleLine} />
          </View>

          {/* The slot */}
          <View style={styles.slot}>
            <View style={styles.slotLip} />
            <Animated.View style={[styles.scanBar, scanStyle]} />
          </View>
        </View>

        {/* Controls appear once the receipt has finished printing. */}
        <Animated.View style={[styles.controls, controlsStyle]} pointerEvents={phase === 'done' ? 'auto' : 'none'}>
          <PressableScale style={[styles.button, styles.secondary]} onPress={onPrintForReal}>
            <Ionicons name="open-outline" size={18} color="#f5f5f5" />
            <Text style={styles.secondaryText}>
              {Platform.OS === 'web' ? 'Open print dialog' : 'Send to printer'}
            </Text>
          </PressableScale>
          <PressableScale style={[styles.button, styles.primary]} onPress={handleTearOff}>
            <Ionicons name="cut-outline" size={20} color="#111" />
            <Text style={styles.primaryText}>Tear off</Text>
          </PressableScale>
        </Animated.View>
      </Animated.View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(8,8,10,0.72)',
  },
  feedWindow: {
    position: 'absolute',
    top: BEZEL_HEIGHT - 4,
    left: 0,
    right: 0,
    bottom: 0,
    overflow: 'hidden',
    alignItems: 'center',
  },
  paperWrap: {
    width: PAPER_WIDTH,
    alignItems: 'center',
  },
  paper: {
    width: PAPER_WIDTH,
    backgroundColor: '#ffffff',
    shadowColor: '#000',
    shadowOpacity: 0.35,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 10 },
    elevation: 10,
  },
  tornEdge: {
    marginTop: -1,
  },
  bezel: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: BEZEL_HEIGHT,
    backgroundColor: '#141416',
    borderBottomLeftRadius: 22,
    borderBottomRightRadius: 22,
    paddingHorizontal: 20,
    paddingTop: 14,
    justifyContent: 'space-between',
    shadowColor: '#000',
    shadowOpacity: 0.5,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 6 },
    elevation: 12,
  },
  bezelTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  brandRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  brand: {
    color: '#c8c8c8',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 1,
  },
  ledRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  led: {
    width: 9,
    height: 9,
    borderRadius: 5,
    backgroundColor: '#4ade80',
    shadowColor: '#4ade80',
    shadowOpacity: 0.9,
    shadowRadius: 6,
  },
  ledLabel: {
    color: '#8a8a8a',
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 1.5,
  },
  grille: {
    gap: 4,
    marginBottom: 6,
  },
  grilleLine: {
    height: 2,
    borderRadius: 1,
    backgroundColor: '#242427',
  },
  slot: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: -2,
    height: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  slotLip: {
    width: PAPER_WIDTH + 24,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#050506',
    borderTopWidth: 1,
    borderTopColor: '#2c2c30',
    overflow: 'hidden',
  },
  scanBar: {
    position: 'absolute',
    width: 60,
    height: 6,
    borderRadius: 3,
    backgroundColor: '#4ade80',
  },
  controls: {
    position: 'absolute',
    left: 20,
    right: 20,
    bottom: 40,
    flexDirection: 'row',
    gap: 12,
  },
  button: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 16,
    borderRadius: 14,
  },
  primary: {
    backgroundColor: '#f5f5f5',
  },
  secondary: {
    backgroundColor: '#2a2a2e',
  },
  primaryText: {
    color: '#111',
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryText: {
    color: '#f5f5f5',
    fontSize: 16,
    fontWeight: '600',
  },
});
