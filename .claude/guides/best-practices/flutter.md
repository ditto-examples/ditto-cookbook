# Flutter Best Practices for Claude Code

> **Note**: This document is a living guide designed primarily for Claude Code to reference when implementing Flutter features in the Ditto Cookbook project. It combines patterns from **Flutter Official**, **Dart Official**, and **Riverpod Official** documentation with practical, production-tested approaches. While comprehensive, it's not exhaustive—use your judgment and always verify with official documentation when uncertain.

## Goals

This guide helps achieve:

- **Change Resilient**: Code that doesn't break with spec changes or feature additions
- **Bug Localization**: SSOT (Single Source of Truth) and clear separation of responsibilities
- **Testability**: Clear boundaries with dependency injection
- **Performance**: Controlled build costs and efficient rebuilds
- **Riverpod Safety**: Robust against Riverpod 3.x lifecycle (auto-retry, etc.)

---

## Architecture Standards

### Layer Definitions

**Three Core Layers:**

1. **UI Layer**: Widgets, UI state (display logic, input validation), UI event routing
2. **Data Layer**: Repository + Service for external I/O, caching, retry, transformation, polling
3. **Domain Layer** (Optional): Domain models, UseCases for complex rules (only when necessary)

### SSOT (Single Source of Truth)

**✅ DO:**
- Have exactly one SSOT per data type
- Only SSOT can modify that data type
- Repository typically serves as SSOT

**❌ DON'T:**
- Create multiple sources that can modify the same data type
- Bypass Repository to directly modify data from UI

**Why**: Flutter official documentation explicitly defines Repository as SSOT for the Data Layer, preventing inconsistent state and simplifying bug tracking.

---

## Folder Structure

### Recommended Structure (Medium to Large Scale)

```
lib/
  app/
    app.dart
  data/
    services/
      api_client.dart
      auth_service.dart
    repositories/
      user_repository.dart
      theme_repository.dart
  domain/
    models/
      user.dart
      theme_settings.dart
  ui/
    profile/
      profile_page.dart
      profile_controller.dart
      profile_providers.dart
      profile_models.dart    # UI-specific models (optional)
    login/
      login_page.dart
      login_controller.dart
      login_providers.dart
test/
  data/
  ui/
integration_test/
```

**✅ DO:**
- Organize UI by feature (profile, login, etc.)
- Keep Data layer components shared across features
- Place domain models in dedicated `domain/models/` directory

**❌ DON'T:**
- Import `lib/src` from other packages (violates Dart's `implementation_imports` lint)
- Mix layers within feature folders

**Why**: Feature-based UI organization improves maintainability, while shared Data layer prevents duplication. Clear separation enables independent testing of each layer.

---

## Riverpod Standards

### Provider Definition

**✅ DO:**
- Define providers as **top-level final** or use **@riverpod** code generation
- Perform `ref.watch/read/listen` on statically known providers

```dart
// ✅ GOOD: Top-level final provider
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(apiClientProvider));
});

// ✅ GOOD: Code generation
@riverpod
FutureOr<User> currentUser(CurrentUserRef ref) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.fetchMe();
}
```

**❌ DON'T:**
- Generate providers dynamically (in class fields, inside functions)

```dart
// ❌ BAD: Dynamic provider generation
class MyWidget extends StatelessWidget {
  final provider = Provider<int>((ref) => 42); // Memory leak risk!
}

// ❌ BAD: Creating providers in functions
Provider<T> createProvider<T>(T value) {
  return Provider<T>((ref) => value); // Unpredictable behavior!
}
```

**Why**: Riverpod requires static analysis for riverpod_lint. Dynamic providers can cause memory leaks and are not analyzable.

---

### Side Effects in Providers

**❌ DON'T (CRITICAL):**
- Execute side effects (POST, billing, logging, navigation) during Provider initialization

```dart
// ❌ BAD: Side effect in provider initialization
final badProvider = FutureProvider<void>((ref) async {
  await http.post('https://api.example.com/log'); // NG!
  await analytics.send('event'); // NG!
});
```

**✅ DO:**
- Design provider body as "read" operation
- Expose side effects as (Async)Notifier methods
- Call methods from UI events

```dart
// ✅ GOOD: Side effects in Notifier methods
@riverpod
class ProfileController extends _$ProfileController {
  @override
  FutureOr<void> build() {} // No side effects here

  Future<void> saveName(String name) async {
    final repo = ref.read(userRepositoryProvider);
    await repo.updateMe(name: name); // Side effect in method
    ref.invalidate(currentUserProvider);
  }
}

// ✅ GOOD: Call from UI event
ElevatedButton(
  onPressed: () async {
    await ref.read(profileControllerProvider.notifier).saveName(name);
  },
  child: const Text('Save'),
)
```

**Why**: Riverpod 3.0 auto-retries failed providers with exponential backoff. Side effects in initialization may execute multiple times unexpectedly. Providers fundamentally represent "read" operations per official documentation.

---

### Widget Initialization of Providers

**❌ DON'T:**
- Initialize providers from Widget lifecycle methods

```dart
// ❌ BAD: Widget initializing provider
class MyWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends ConsumerState<MyWidget> {
  @override
  void initState() {
    super.initState();
    ref.read(myProvider).init(); // Race conditions!
  }
}
```

**✅ DO:**
- Let providers initialize themselves declaratively
- For startup warmup, read at app root (eager initialization)

```dart
// ✅ GOOD: Eager initialization at root (if absolutely necessary)
class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(startupProvider); // Warmup at root
    return MaterialApp(/* ... */);
  }
}
```

**Exception**: Only for cache/connection preparation at startup, never for side effects.

**Why**: Widget-initiated provider initialization causes race conditions and unexpected behavior per Riverpod official documentation.

---

### Ephemeral State in Providers

**❌ DON'T:**
- Store short-lived UI state in providers

```dart
// ❌ BAD: Ephemeral state in provider
final textFieldValueProvider = StateProvider<String>((ref) => ''); // NG!
final selectedTabProvider = StateProvider<int>((ref) => 0); // NG!
final animationControllerProvider = Provider<AnimationController>(...); // NG!
```

**✅ DO:**
- Keep ephemeral state in Widget local state (StatefulWidget)
- Only put "app state" that needs sharing in providers

```dart
// ✅ GOOD: Local state for TextField
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _controller = TextEditingController(); // Local state

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(controller: _controller);
  }
}
```

**Why**: Riverpod official DO/DON'T explicitly marks ephemeral state in providers as an anti-pattern.

---

### ref.watch / ref.read / ref.listen Usage

**ref.watch (Standard):**

```dart
// ✅ GOOD: watch for reactive updates
@override
Widget build(BuildContext context, WidgetRef ref) {
  final user = ref.watch(currentUserProvider);
  return Text(user.name);
}
```

**ref.read (Limited to Events):**

```dart
// ✅ GOOD: read once within event handler
onPressed: () {
  final value = ref.read(counterProvider);
  print(value);
}

// ❌ BAD: read in build (UI won't update)
@override
Widget build(BuildContext context, WidgetRef ref) {
  final user = ref.read(currentUserProvider); // NG!
  return Text(user.name);
}
```

**ref.listen (Side Effects Only):**

```dart
// ✅ GOOD: listen for side effects
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.listen(profileControllerProvider, (prev, next) {
    if (next.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${next.error}')),
      );
    }
  });
  return /* ... */;
}
```

**Why**: Riverpod official documentation defines watch as standard for declarative observation, read for one-time reads in events, and listen exclusively for side effects like dialogs and navigation.

---

### Rebuild Optimization with select

**✅ DO:**
- Use `select` to narrow observation scope when rebuilds are costly

```dart
// ✅ GOOD: select to observe only specific field
final userName = ref.watch(userProvider.select((user) => user.name));
```

**Note**: Measure before optimizing. Most widgets rebuild efficiently without `select`.

---

### family (Parameterized Providers)

**✅ DO:**
- Use types with stable `==` / `hashCode` for family arguments
- Combine family with `autoDispose` to prevent memory leaks

```dart
// ✅ GOOD: Stable types (int, String, immutable objects)
@riverpod
FutureOr<Item> item(ItemRef ref, int itemId) async {
  return repository.fetchItem(itemId);
}

// ✅ GOOD: With autoDispose
final itemProvider = FutureProvider.autoDispose.family<Item, int>((ref, id) async {
  return repository.fetchItem(id);
});
```

**❌ DON'T:**
- Use unstable types (List, Map with new instance each time)

```dart
// ❌ BAD: Unstable equality
final badProvider = Provider.family<Data, List<int>>((ref, list) {
  // New List instance each time = different provider!
});
```

**Why**: family arguments are Map keys internally. Unstable equality means providers are treated as different instances. Official documentation explicitly warns about this.

---

### autoDispose / onDispose Safety

**✅ DO:**
- Use `ref.onDispose` exclusively for cleanup

```dart
// ✅ GOOD: Cleanup in onDispose
@riverpod
Stream<Data> dataStream(DataStreamRef ref) {
  final controller = StreamController<Data>();

  ref.onDispose(() {
    controller.close(); // Cleanup only
  });

  return controller.stream;
}
```

**❌ DON'T:**
- Cause side effects in onDispose callbacks

```dart
// ❌ BAD: Side effects in onDispose
ref.onDispose(() {
  http.post('https://api.example.com/cleanup'); // NG!
  ref.invalidate(otherProvider); // NG!
});
```

**Why**: Official documentation warns against side effects in onDispose as they can cause unpredictable behavior.

---

## Flutter Implementation Standards

### build() Method Performance

**❌ DON'T:**
- Perform high-cost processing in build()

```dart
// ❌ BAD: Heavy processing in build
@override
Widget build(BuildContext context) {
  final data = jsonDecode(heavyJsonString); // NG!
  final result = complexCalculation(); // NG!
  return Text('$result');
}
```

**✅ DO:**
- Move heavy processing outside build()
- Cache results
- Split into smaller widgets

```dart
// ✅ GOOD: Heavy processing in provider
final processedDataProvider = Provider<Data>((ref) {
  return processHeavyData(rawData);
});

@override
Widget build(BuildContext context, WidgetRef ref) {
  final data = ref.watch(processedDataProvider);
  return Text('$data');
}
```

**Why**: Flutter official Performance best practices explicitly states to avoid repetitive cost in build() as it's called frequently.

---

### BuildContext Safety

**❌ DON'T:**
- Use BuildContext across async gaps without checking mounted

```dart
// ❌ BAD: BuildContext used after async without check
Future<void> onPressed() async {
  await Future.delayed(Duration(seconds: 1));
  Navigator.of(context).push(...); // May crash if widget disposed!
}
```

**✅ DO:**
- Check mounted before using context after async
- Pass context as parameter when needed

```dart
// ✅ GOOD: Check mounted
Future<void> onPressed() async {
  await Future.delayed(Duration(seconds: 1));
  if (!mounted) return;
  Navigator.of(context).push(...);
}

// ✅ GOOD: Use context before async
Future<void> onPressed() async {
  final navigator = Navigator.of(context); // Capture before async
  await Future.delayed(Duration(seconds: 1));
  navigator.push(...);
}
```

**Why**: BuildContext becomes invalid after widget disposal. Using it can cause runtime errors.

---

### Key Usage

**✅ DO:**
- Use keys to preserve widget state during reordering
- Prefer ValueKey for list items with unique identifiers
- Use GlobalKey sparingly (high memory overhead)

```dart
// ✅ GOOD: ValueKey for list items
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    final item = items[index];
    return ListTile(
      key: ValueKey(item.id),
      title: Text(item.name),
    );
  },
)
```

**Why**: Keys help Flutter identify which widgets to preserve, update, or remove when the widget tree changes.

---

### Equatable for Value Objects

**✅ DO:**
- Use Equatable for model classes to enable value equality

```dart
// ✅ GOOD: Equatable for value equality
import 'package:equatable/equatable.dart';

class User extends Equatable {
  const User({required this.id, required this.name});
  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

// Now comparison works as expected
final user1 = User(id: '1', name: 'Alice');
final user2 = User(id: '1', name: 'Alice');
print(user1 == user2); // true
```

**❌ DON'T:**
- Compare model objects without implementing equality

```dart
// ❌ BAD: Default reference equality
class User {
  const User({required this.id, required this.name});
  final String id;
  final String name;
}

final user1 = User(id: '1', name: 'Alice');
final user2 = User(id: '1', name: 'Alice');
print(user1 == user2); // false (different instances)
```

**Why**: Value equality is essential for widget rebuilds, provider comparisons, and testing. Equatable simplifies implementation and reduces boilerplate.

---

### AsyncValue Pattern

**✅ DO:**
- Handle all AsyncValue states explicitly (loading, error, data)
- Use pattern matching for cleaner code (Dart 3.0+)
- Transform data with `whenData` when needed

```dart
// ✅ GOOD: Pattern matching (Dart 3.0+)
@override
Widget build(BuildContext context, WidgetRef ref) {
  final userAsync = ref.watch(currentUserProvider);

  return switch (userAsync) {
    AsyncData(:final value) => UserProfile(user: value),
    AsyncError(:final error) => ErrorView(error: error),
    _ => const LoadingView(),
  };
}

// ✅ GOOD: Traditional when method
@override
Widget build(BuildContext context, WidgetRef ref) {
  final userAsync = ref.watch(currentUserProvider);

  return userAsync.when(
    data: (user) => UserProfile(user: user),
    loading: () => const LoadingView(),
    error: (error, stack) => ErrorView(error: error),
  );
}
```

**Why**: Exhaustive AsyncValue handling prevents null errors and improves user experience with proper loading and error states.

---

### Widget Splitting and const

**✅ DO:**
- Split large widgets into smaller ones
- Use const constructors wherever possible

```dart
// ✅ GOOD: Split and const-ify
class UserProfile extends StatelessWidget {
  const UserProfile({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const UserAvatar(), // const widget
        UserName(name: user.name),
        const UserActions(), // const widget
      ],
    );
  }
}
```

**Why**: Smaller widgets reduce rebuild scope and improve readability. const widgets are reused, reducing rebuild load per Flutter official UI best practices.

---

### Cache Management

**✅ DO:**
- Align cache strategy with SSOT
- Control cache on Repository side

```dart
// ✅ GOOD: Cache managed by Repository (SSOT)
class UserRepository {
  User? _cached;

  Future<User> fetchMe() async {
    if (_cached != null) return _cached!;
    final json = await _api.getJson('/me');
    final user = User.fromJson(json);
    _cached = user;
    return user;
  }

  void clearCache() {
    _cached = null;
  }
}
```

**❌ DON'T:**
- Cache in multiple places
- Cache without invalidation strategy

**Why**: Flutter official documentation warns about stale cache risks. Repository as SSOT ensures consistent cache invalidation.

---

## Testing Strategy

### Test Pyramid

**Investment Allocation:**
- **More**: Unit tests and Widget tests
- **Less**: Integration tests (critical paths only)

**Why**: Flutter official Testing overview shows this trade-off with cost/confidence table.

---

### Unit Testing

**✅ DO:**
- Test ViewModel/Controller logic without Flutter dependencies
- Mock repositories with Fake/Mock

```dart
// ✅ GOOD: Unit test with ProviderContainer
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeUserRepository implements UserRepository {
  @override
  Future<User> fetchMe() async => const User(id: '1', name: 'Test');
}

void main() {
  test('currentUserProvider returns user', () async {
    final container = ProviderContainer(
      overrides: [
        userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      ],
    );
    addTearDown(container.dispose);

    final user = await container.read(currentUserProvider.future);
    expect(user.name, 'Test');
  });
}
```

**Why**: Flutter official case study explicitly recommends unit testing each layer with minimal dependencies.

---

### Widget Testing

**✅ DO:**
- Use `testWidgets` to verify display and interactions
- Test all AsyncValue states (loading, error, data)
- Use `pumpAndSettle` for animations, `pump` for manual frame control

```dart
// ✅ GOOD: Comprehensive widget test
testWidgets('Profile page displays user name', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) async =>
          const User(id: '1', name: 'Alice')),
      ],
      child: const MaterialApp(home: ProfilePage()),
    ),
  );

  // Test loading state
  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  // Wait for data to load
  await tester.pumpAndSettle();

  // Test data state
  expect(find.text('Alice'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
});

// ✅ GOOD: Test error state
testWidgets('Profile page shows error', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) async =>
          throw Exception('Network error')),
      ],
      child: const MaterialApp(home: ProfilePage()),
    ),
  );

  await tester.pumpAndSettle();
  expect(find.textContaining('Error'), findsOneWidget);
});

// ✅ GOOD: Test interactions
testWidgets('Save button updates user', (tester) async {
  var saveCalled = false;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileControllerProvider.overrideWith(() {
          return TestProfileController(() => saveCalled = true);
        }),
      ],
      child: const MaterialApp(home: ProfilePage()),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();

  expect(saveCalled, isTrue);
});
```

**Why**: Flutter official cookbook explains Widget test procedures and concepts. Comprehensive testing ensures reliability across all states.

---

### Integration Testing

**✅ DO:**
- Verify critical paths only with `integration_test`
- Automate performance measurement if needed

**Why**: Integration tests are expensive to maintain. Official guides recommend focusing on critical flows.

---

## Lint Standards

### Required Lints

1. **flutter_lints**: Use as baseline

```yaml
# ✅ GOOD: analysis_options.yaml
include: package:flutter_lints/flutter.yaml
```

2. **implementation_imports**: Prohibit lib/src imports from other packages

```yaml
linter:
  rules:
    - implementation_imports
```

3. **riverpod_lint**: Enable for static analysis (if using Riverpod)

**Why**: Flutter official documentation defines flutter_lints as "latest recommended lint set". Dart official documentation explains implementation_imports rationale.

---

### CI Requirements

**MUST Execute:**
- `flutter analyze`
- `flutter test`
- `flutter test integration_test` (critical paths, in necessary environments)

---

## Complete Implementation Template

### Example: Profile Feature (User Fetch + Update)

#### 1. Service Layer

```dart
// data/services/api_client.dart
class ApiClient {
  Future<Map<String, dynamic>> getJson(String path) async {
    // HTTP GET implementation
    throw UnimplementedError();
  }

  Future<void> postJson(String path, Map<String, dynamic> body) async {
    // HTTP POST implementation
    throw UnimplementedError();
  }
}
```

#### 2. Domain Model

```dart
// domain/models/user.dart
class User {
  const User({required this.id, required this.name});
  final String id;
  final String name;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
```

#### 3. Repository (SSOT)

```dart
// data/repositories/user_repository.dart
import '../../domain/models/user.dart';
import '../services/api_client.dart';

class UserRepository {
  UserRepository(this._api);
  final ApiClient _api;

  User? _cached;

  Future<User> fetchMe() async {
    if (_cached != null) return _cached!;
    final json = await _api.getJson('/me');
    final user = User.fromJson(json);
    _cached = user;
    return user;
  }

  Future<User> updateMe({required String name}) async {
    await _api.postJson('/me', {'name': name});
    final json = await _api.getJson('/me');
    final user = User.fromJson(json);
    _cached = user;
    return user;
  }

  void clearCache() {
    _cached = null;
  }
}
```

#### 4. Providers (DI and Read)

```dart
// ui/profile/profile_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/api_client.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/user.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(apiClientProvider));
});

final currentUserProvider = FutureProvider.autoDispose<User>((ref) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.fetchMe();
});
```

#### 5. Controller (Side Effects)

```dart
// ui/profile/profile_controller.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'profile_providers.dart';

part 'profile_controller.g.dart';

@riverpod
class ProfileController extends _$ProfileController {
  @override
  FutureOr<void> build() {}

  Future<void> saveName(String name) async {
    final repo = ref.read(userRepositoryProvider);
    await repo.updateMe(name: name);
    ref.invalidate(currentUserProvider);
  }
}
```

#### 6. UI (watch + listen)

```dart
// ui/profile/profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'profile_controller.dart';
import 'profile_providers.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    ref.listen(profileControllerProvider, (prev, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${next.error}')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: userAsync.when(
        data: (user) {
          _controller.text = user.name;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('User: ${user.id}'),
                TextField(controller: _controller),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    await ref
                        .read(profileControllerProvider.notifier)
                        .saveName(_controller.text);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
```

---

## Anti-Pattern Detection Checklist

### Immediate Rejection (CRITICAL)

- [ ] Side effects (POST, billing, logging) in Provider initialization
- [ ] Widget initializing Provider from initState
- [ ] Dynamic provider generation (in class fields, functions)
- [ ] Side effects in onDispose callbacks
- [ ] Heavy processing (JSON parsing, large loops, I/O) in build()
- [ ] Using BuildContext after async without mounted check
- [ ] Modifying collections/maps used as provider keys

### High-Priority Issues

- [ ] Ephemeral state (TextField, tabs, AnimationController) in Providers
- [ ] Unstable family arguments (new List/Map instances)
- [ ] Using ref.read in build() method
- [ ] Multiple SSOTs for same data type
- [ ] Importing lib/src from other packages
- [ ] Missing const constructors for stateless widgets
- [ ] Not handling all AsyncValue states (loading, error, data)
- [ ] Model classes without value equality (should use Equatable or override ==)

### Medium-Priority Issues

- [ ] Large build() methods (>50 lines) - should split into smaller widgets
- [ ] Widgets without keys in reorderable lists
- [ ] Excessive use of GlobalKey
- [ ] setState called with complex logic (should extract to method)
- [ ] Missing dispose() for controllers (TextEditingController, AnimationController)
- [ ] Direct Navigator.of(context) usage in async callbacks without safety checks

---

## Quick Reference for Claude Code

**Essential checklist when implementing Flutter features:**

### Architecture & State Management
1. ✅ Follow Flutter official architecture: UI → Data (Repository as SSOT) → Domain
2. ✅ Repository is SSOT—all mutations go through Repository only
3. ✅ Providers are top-level final or @riverpod (never dynamic generation)
4. ✅ **CRITICAL**: Provider body is "read only" (no side effects in initialization)
5. ✅ Expose side effects as (Async)Notifier methods, call from UI events
6. ✅ Remember Riverpod 3.0 auto-retry: side effects in initialization may run multiple times

### Riverpod Usage
7. ✅ Use ref.watch as standard, ref.listen for side effects only
8. ✅ **Never use ref.read in build()** - use ref.watch instead
9. ✅ Keep ephemeral state (TextField, tabs, AnimationController) in Widget local state
10. ✅ Use stable types (int, String, immutable objects) for family parameters
11. ✅ Combine family with autoDispose to prevent memory leaks

### Widget Best Practices
12. ✅ Split widgets small (under 50 lines per build method), use const where possible
13. ✅ **Check mounted before using BuildContext after async operations**
14. ✅ Use ValueKey for list items to preserve state during reordering
15. ✅ Handle all AsyncValue states: loading, error, and data
16. ✅ Use Equatable for model classes to enable value equality

### Performance
17. ✅ No heavy processing in build() (move to providers or outside build)
18. ✅ Use const constructors for stateless widgets
19. ✅ Use select to narrow observation scope when rebuilds are costly

### Testing
20. ✅ Test with Unit/Widget focus, Integration for critical paths only
21. ✅ Test all AsyncValue states in widget tests
22. ✅ Use ProviderContainer for unit tests, ProviderScope for widget tests

### Code Quality
23. ✅ Enable flutter_lints, implementation_imports, and riverpod_lint
24. ✅ Dispose controllers (TextEditingController, AnimationController)
25. ✅ Never import lib/src from other packages

---

## References

- [Flutter Official Documentation](https://flutter.dev/docs)
- [Riverpod Official Documentation](https://riverpod.dev)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Flutter Performance Best Practices](https://flutter.dev/docs/perf/best-practices)
- [Flutter Testing Guide](https://flutter.dev/docs/testing)
