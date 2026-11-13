import 'react-native-get-random-values';
import { v4 as uuidv4 } from 'uuid';

// A random (version 4) UUID for every new document.
export function newId(): string {
  return uuidv4();
}

// ISO 8601 UTC with exactly millisecond precision, e.g. "2026-10-08T10:30:00.123Z".
export function utcTimestamp(date: Date = new Date()): string {
  return date.toISOString();
}
