# Line Notices

React Native app for the shift notice boards of a factory's production lines.
Version 1.9 runs on the shared tablets of 14 lines; the tablets of a line sync with
each other over the local network and with Ditto Server when the network allows.

- Each notice belongs to one board (`boardId`, one per production line, never changes).
- Each tablet is mounted at one line and shows only that line's board; it never
  moves to another line.
- Only the author of a notice edits it, on the tablet where they wrote it, and
  archiving a notice is the author's action too.
- Archived notices are deleted for good by a retention job on Ditto Server 90 days
  after `deletedAt`; that job is not part of this repository.
- Opening Ditto, authentication, and sync start live in the app shell, which is not
  part of this review. After every `Ditto.open()`, it creates a new `NoticeSync` for
  that instance and calls `enterBoard`.

This change set is the data layer for notices only, in `src/`.
