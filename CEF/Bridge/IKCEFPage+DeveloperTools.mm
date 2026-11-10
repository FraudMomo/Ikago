#import "IKCEFPageInternal.h"

@implementation IKCEFPage (DeveloperTools)
- (BOOL)devToolsVisible { return self.ready && _browser->GetHost()->HasDevTools(); }
- (void)setDeveloperToolsEnabled:(BOOL)enabled {
  _developerTools = enabled;
  if (!enabled && self.ready) _browser->GetHost()->CloseDevTools();
}
- (void)toggleDevTools {
  if (!self.ready || !_developerTools) return;
  if (self.devToolsVisible) { _browser->GetHost()->CloseDevTools(); return; }
  [self inspectAtPoint:NSMakePoint(-1, -1)];
}
- (void)inspectAtPoint:(NSPoint)point {
  if (!self.ready || !_developerTools) return;
  CefWindowInfo window;
  window.hidden = true;
  CefBrowserSettings settings;
  CefPoint location;
  if (point.x >= 0 && point.y >= 0) location = CefPoint(point.x, point.y);
  _browser->GetHost()->ShowDevTools(window, IKCEFMakeInspectorClient(self), settings, location);
}
@end
