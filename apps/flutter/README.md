# Flutter Apps - Ditto Cookbook

This directory contains Flutter applications demonstrating Ditto SDK integration for mobile platforms (iOS and Android). These apps showcase offline-first, real-time synchronization patterns suitable for production use.

## Overview

Flutter apps in this cookbook demonstrate:

- **Offline-First Architecture**: Apps that work seamlessly without network connectivity
- **Real-Time Sync**: Live data updates across devices using Ditto's mesh networking
- **Mobile Best Practices**: iOS and Android platform-specific implementations
- **State Management**: Integration of Ditto with modern Flutter state management solutions
- **Testing Strategies**: Comprehensive test coverage for sync-enabled applications

## Prerequisites

### Required Software

1. **Flutter SDK**: Version 3.24.0 or higher
   - Install from [flutter.dev](https://flutter.dev/docs/get-started/install)
   - Verify: `flutter --version`

2. **Dart SDK**: Version 3.5.0 or higher (included with Flutter)
   - Verify: `dart --version`

3. **Platform-Specific Tools**:

   **For iOS Development**:
   - macOS (required for iOS development)
   - Xcode 15.0 or higher
   - CocoaPods: `sudo gem install cocoapods`
   - iOS Simulator or physical device

   **For Android Development**:
   - Android Studio or Android SDK Command-line Tools
   - Android SDK 34 (API level 34) or higher
   - Android Emulator or physical device
   - Java Development Kit (JDK) 11 or higher

4. **IDE** (recommended):
   - [Visual Studio Code](https://code.visualstudio.com/) with Flutter extension
   - [Android Studio](https://developer.android.com/studio) with Flutter plugin

### Ditto Account Setup

1. Create a Ditto account at [portal.ditto.live](https://portal.ditto.live)
2. Create a new app in the Ditto Portal
3. Obtain your credentials:
   - Database ID
   - Auth URL
   - Websocket URL
   - Online Playground Token

## Environment Setup

### 1. Configure Environment Variables

All Flutter apps require Ditto credentials configured via environment variables.

```bash
# From the repository root
cp .env.template .env

# Edit .env with your actual Ditto credentials
# NEVER commit .env to version control
```

Required variables in `.env`:

```bash
DITTO_DATABASE_ID=your_database_id_here
DITTO_AUTH_URL=https://auth.example.ditto.live
DITTO_WEBSOCKET_URL=wss://sync.example.ditto.live
DITTO_ONLINE_PLAYGROUND_TOKEN=your_playground_token_here
```

### 2. Install Flutter Dependencies

Navigate to the specific app directory and run:

```bash
cd apps/flutter/<app-name>
flutter pub get
```

### 3. Platform-Specific Setup

**iOS**:
```bash
cd ios
pod install
cd ..
```

**Android**:
No additional setup required. Gradle will download dependencies on first build.

## Running Apps

### iOS

```bash
# List available iOS simulators
flutter devices

# Run on iOS simulator
flutter run -d "iPhone 15 Pro"

# Run on physical iOS device (requires provisioning)
flutter run -d <device-id>
```

### Android

```bash
# List available Android devices/emulators
flutter devices

# Run on Android emulator
flutter run -d emulator-5554

# Run on physical Android device (enable USB debugging)
flutter run -d <device-id>
```

### Debug vs Release Mode

```bash
# Debug mode (default) - includes hot reload
flutter run

# Profile mode - performance profiling
flutter run --profile

# Release mode - optimized build
flutter run --release
```

## Ditto SDK Integration

### SDK Installation

Each Flutter app includes the Ditto SDK via `pubspec.yaml`:

```yaml
dependencies:
  ditto_flutter: ^latest_version
```

Check [pub.dev/packages/ditto_flutter](https://pub.dev/packages/ditto_flutter) for the latest version.

### Initialization Pattern

Common Ditto initialization pattern used across apps:

```dart
import 'package:ditto_flutter/ditto_flutter.dart';

// Initialize Ditto (typically in main.dart or a service)
final ditto = await Ditto.open(
  identity: OnlinePlayground(
    appId: Platform.environment['DITTO_DATABASE_ID']!,
    token: Platform.environment['DITTO_ONLINE_PLAYGROUND_TOKEN']!,
  ),
);

// Start sync
await ditto.startSync();
```

### Offline-First Patterns

Apps demonstrate:
- Local-first data operations (insert, update, delete)
- Background synchronization
- Conflict resolution strategies
- Network state handling
- Persistence configuration

### Real-Time Observers

Live query pattern for reactive UI:

```dart
// Subscribe to collection changes
final subscription = ditto
    .store
    .collection('orders')
    .find('status == "active"')
    .observe((docs) {
      // Update UI with new data
      setState(() {
        orders = docs.map((doc) => Order.fromDitto(doc)).toList();
      });
    });

// Don't forget to cancel subscription
subscription.cancel();
```

## State Management

### Recommended: Riverpod 2.x

For complex applications (like POS/KDS systems), we recommend **Riverpod** for:

- **Type Safety**: Compile-time checked state management
- **Testability**: Easy mocking and testing of business logic
- **Ditto Integration**: Clean separation of sync layer from UI state
- **DevTools**: Excellent debugging support
- **Performance**: Efficient rebuilds for real-time updates

**Alternative Options**:
- **Bloc**: Event-driven architecture for transactional flows
- **Provider**: Simpler approach for smaller applications

### Integration Pattern

```dart
// Riverpod provider for Ditto service
final dittoProvider = Provider<DittoService>((ref) {
  return DittoService(ditto: ref.read(dittoInstanceProvider));
});

// State notifier for real-time data
final ordersProvider = StateNotifierProvider<OrdersNotifier, List<Order>>((ref) {
  return OrdersNotifier(ref.read(dittoProvider));
});
```

See individual app READMEs for specific state management implementations.

## Testing

### Test Coverage Target

All Flutter apps target **80%+ test coverage** including:

- **Unit Tests**: Business logic, data models, utilities
- **Widget Tests**: UI components and screens
- **Integration Tests**: End-to-end flows with Ditto sync

### Running Tests for All Flutter Apps

From the repository root, run tests for all Flutter apps in parallel:

```bash
./scripts/test-all.sh
```

This command automatically discovers and tests all Flutter apps with fail-fast behavior.

### Running Tests for a Single App

Navigate to the specific app directory:

```bash
cd apps/flutter/<app-name>

# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage

# View coverage report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Testing with Ditto

Mock Ditto operations in tests:

```dart
// Use mockito or mocktail for mocking
class MockDitto extends Mock implements Ditto {}

// Test with mocked Ditto instance
test('orders are loaded correctly', () {
  final mockDitto = MockDitto();
  when(() => mockDitto.store.collection('orders').find())
      .thenAnswer((_) => mockDocuments);

  // Test your logic
});
```

## Project Structure

Typical Flutter app structure in this repository:

```
app-name/
├── ARCHITECTURE.md           # Detailed architecture documentation
├── README.md                 # App-specific getting started guide
├── pubspec.yaml              # Dependencies and project metadata
├── lib/
│   ├── main.dart            # App entry point
│   ├── models/              # Data models
│   ├── services/            # Business logic & Ditto integration
│   ├── providers/           # State management (Riverpod/Provider)
│   ├── ui/                  # Screens and widgets
│   │   ├── screens/        # Full-screen views
│   │   └── widgets/        # Reusable UI components
│   └── utils/              # Helper functions and utilities
├── test/
│   ├── unit/               # Unit tests
│   ├── widget/             # Widget tests
│   └── integration/        # Integration tests
├── ios/                    # iOS platform-specific files
├── android/                # Android platform-specific files
└── .gitignore             # Git ignore rules
```

## Common Issues and Troubleshooting

### Ditto Sync Not Working

1. **Check Credentials**: Verify `.env` has correct Ditto credentials
2. **Network Permissions**: Ensure app has network permissions in manifests
3. **Simulator Networking**: iOS Simulator may need network reset
4. **Firewall**: Check firewall isn't blocking WebSocket connections

### iOS Build Failures

1. **CocoaPods**: Run `pod install` in `ios/` directory
2. **Xcode Version**: Ensure Xcode 15+ is installed
3. **Signing**: Configure development team in Xcode
4. **Deployment Target**: Check minimum iOS version in Podfile

### Android Build Failures

1. **SDK Version**: Ensure Android SDK 34+ is installed
2. **Gradle Version**: Check `gradle/wrapper/gradle-wrapper.properties`
3. **Java Version**: Verify JDK 11+ is installed
4. **Memory**: Increase Gradle memory in `gradle.properties`

### Hot Reload Issues

1. **Ditto State**: Hot reload may not reinitialize Ditto correctly
2. **Solution**: Use hot restart (Shift + R in Flutter DevTools)
3. **Observers**: Cancel and resubscribe to Ditto observers after restart

### Performance Issues

1. **Debug Mode**: Always test performance in profile/release mode
2. **Observers**: Limit number of active Ditto observers
3. **Query Optimization**: Use selective queries instead of fetching all documents
4. **Rebuild Optimization**: Use `const` constructors where possible

## Best Practices

### Ditto Integration

1. **Single Instance**: Initialize Ditto once and share via dependency injection
2. **Lifecycle Management**: Start sync on app start, stop on app dispose
3. **Observer Cleanup**: Always cancel subscriptions to prevent memory leaks
4. **Error Handling**: Wrap Ditto operations in try-catch blocks
5. **Type Safety**: Use strongly-typed models, not raw Ditto documents

### Flutter Development

1. **State Management**: Separate UI state from business logic
2. **Async Operations**: Use async/await properly with error handling
3. **Widget Composition**: Break down complex UIs into smaller widgets
4. **Performance**: Profile regularly, avoid unnecessary rebuilds
5. **Accessibility**: Support screen readers and dynamic text sizing

### Security

1. **Credentials**: NEVER hardcode credentials in source code
2. **Environment Variables**: Use `.env` for all sensitive configuration
3. **Input Validation**: Validate all user inputs before Ditto operations
4. **Error Messages**: Don't expose sensitive information in error messages

## Resources

### Ditto Documentation

- [Ditto Docs](https://docs.ditto.live)
- [Flutter SDK Reference](https://docs.ditto.live/flutter/latest/)
- [Best Practices](https://docs.ditto.live/best-practices/)
- [Community Forum](https://community.ditto.live)

### Flutter Resources

- [Flutter Docs](https://flutter.dev/docs)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Flutter Cookbook](https://flutter.dev/docs/cookbook)
- [Pub.dev Packages](https://pub.dev)

### State Management

- [Riverpod Documentation](https://riverpod.dev)
- [Bloc Documentation](https://bloclibrary.dev)
- [Provider Documentation](https://pub.dev/packages/provider)

## Apps in This Directory

<!-- Individual app links will be added here as apps are created -->

## Contributing

When adding new Flutter apps:

1. Follow the project structure outlined above
2. Create comprehensive `ARCHITECTURE.md` documentation
3. Include 80%+ test coverage
4. Document Ditto integration patterns
5. Use English for all code and documentation
6. Follow Flutter/Dart style guide

See [../../CLAUDE.md](../../CLAUDE.md) for complete development guidelines.
