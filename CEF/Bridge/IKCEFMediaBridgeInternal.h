#pragma once
#include "include/cef_resource_request_handler.h"
/// The media translation route for this request, or null when it isn't one.
CefRefPtr<CefResourceRequestHandler> IKCEFMediaRoute(CefRefPtr<CefRequest> request, const CefString& initiator);
