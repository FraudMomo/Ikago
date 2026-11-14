#import "IKCEFRuntime.h"
BOOL IKCEFCanCreateContext(NSURL *root);
void IKCEFTrackBrowser(int delta);
void IKCEFClearContexts(void);
/// Applies the stored color scheme to the global context once Chromium is ready (`IKCEFContexts setColorScheme:`).
void IKCEFApplyColorScheme(void);
