library;

/// Stub for non-web platforms (Android, iOS, Desktop).
/// Guarantees that web-specific Firebase plugins are never imported on mobile.

void initFirebaseWebPlugins() {}
