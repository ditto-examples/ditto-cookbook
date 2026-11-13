import type { Ditto, SyncSubscription } from '@dittolive/ditto';

// Owns the subscription of the board that this tablet shows.
// The app shell creates one NoticeSync for each Ditto instance it opens.
export class NoticeSync {
  #ditto: Ditto;
  #subscription: SyncSubscription | null = null;
  #boardId: string | null = null;

  constructor(ditto: Ditto) {
    this.#ditto = ditto;
  }

  // Call after Ditto.open() with the board of the line that the tablet is mounted at.
  enterBoard(boardId: string): void {
    if (boardId === this.#boardId) return; // Already subscribed; do not re-register.
    this.leaveBoard();
    this.#boardId = boardId;
    // Archived notices stay in the subscription, so that every tablet receives the flag.
    this.#subscription = this.#ditto.sync.registerSubscription(
      'SELECT * FROM notices WHERE boardId = :boardId',
      { boardId },
    );
  }

  // Call before the app shell closes Ditto.
  leaveBoard(): void {
    this.#subscription?.cancel();
    this.#subscription = null;
    this.#boardId = null;
  }
}
