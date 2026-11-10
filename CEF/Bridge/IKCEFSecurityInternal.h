#include "include/cef_request_context_handler.h"
#include <vector>
CefRefPtr<CefRequestContextHandler> IKCEFMakeSecurityHandler(NSString *profile);
std::vector<CefRefPtr<CefRequestContext>> IKCEFContextsSnapshot();
void IKCEFSecurityForget(CefRequestContext *context);
void IKCEFSecurityReset();
