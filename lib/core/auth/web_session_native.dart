// Native stub — session idle timeout is handled by the device lock screen
// and biometric/PIN gate on Android/iOS. These are no-ops on native.
void refreshWebSession() {}
bool isWebSessionExpired() => false;
void clearWebSession() {}
