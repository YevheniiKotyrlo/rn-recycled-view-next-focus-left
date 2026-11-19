/**
 * A row of three focusable Pressables: "Target", "Neighbour" and a subject on the right.
 *
 * 1. The old subject has nextFocusLeft pointing at "Target".
 * 2. Once Arrow Left from the old subject has focused "Target", the old subject unmounts, and a
 *    moment later a new subject without nextFocusLeft mounts in its place.
 *
 * Arrow Left from the new subject should land on "Neighbour", the view to its left.
 *
 * @format
 */

import { useEffect, useRef, useState } from 'react';
import {
  findNodeHandle,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';

type Phase = 'old' | 'gap' | 'new';

function App() {
  const target = useRef<View>(null);
  const [targetTag, setTargetTag] = useState<number | null>(null);
  const [phase, setPhase] = useState<Phase>('old');
  const [focused, setFocused] = useState('none');

  useEffect(() => {
    setTargetTag(findNodeHandle(target.current));
  }, []);

  const oldSubjectWasFocused = useRef(false);

  const onFocus = (name: string) => () => {
    console.log(`RecycledFocusReproducer: focused ${name}`);
    setFocused(name);
    if (name === 'Old subject') {
      oldSubjectWasFocused.current = true;
    }
    // Arrow Left from the old subject has reached "Target": swap the subject.
    if (name === 'Target' && phase === 'old' && oldSubjectWasFocused.current) {
      setTimeout(() => setPhase('gap'), 500);
      setTimeout(() => setPhase('new'), 1500);
    }
  };

  return (
    <View style={styles.screen}>
      <Text style={styles.status}>
        {`Phase: ${phase}\nFocused: ${focused}\nTarget tag: ${targetTag}`}
      </Text>
      <View style={styles.row}>
        <Pressable
          ref={target}
          accessibilityLabel="Target"
          onFocus={onFocus('Target')}
          style={styles.box}>
          <Text>Target</Text>
        </Pressable>
        <Pressable
          accessibilityLabel="Neighbour"
          onFocus={onFocus('Neighbour')}
          style={styles.box}>
          <Text>Neighbour</Text>
        </Pressable>
        {phase === 'old' && targetTag != null ? (
          <Pressable
            nativeID="subject-old"
            accessibilityLabel="Old subject"
            nextFocusLeft={targetTag}
            onFocus={onFocus('Old subject')}
            style={styles.box}>
            <Text>Old subject</Text>
          </Pressable>
        ) : null}
        {phase === 'new' ? (
          <Pressable
            nativeID="subject-new"
            accessibilityLabel="New subject"
            onFocus={onFocus('New subject')}
            style={styles.box}>
            <Text>New subject</Text>
          </Pressable>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, padding: 48, backgroundColor: 'white' },
  status: { fontSize: 18, marginBottom: 24, color: 'black' },
  row: { flexDirection: 'row' },
  box: {
    width: 100,
    height: 80,
    marginRight: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#ddd',
  },
});

export default App;
