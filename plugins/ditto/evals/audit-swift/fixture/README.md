# Stock Count

iPad app for warehouse stock counts, built on the Ditto SDK 5.2.0 for Swift.
Version 2.1 is in use in 12 warehouses. During a count, four to eight iPads work
in one warehouse at the same time, mostly over peer-to-peer connections, and sync
with Ditto Server when they reach Wi-Fi. `AppEnvironment.make(config:)` is called
once at launch with the configuration from the app's provisioning code, which is
not part of this package.
