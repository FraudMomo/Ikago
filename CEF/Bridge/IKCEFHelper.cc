// Helper entrypoint only. Build into the CEF helper bundles, never the main app.
#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_process_message.h"
#include <unistd.h>

class RendererIdentity final : public CefApp, public CefRenderProcessHandler {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
  void OnContextCreated(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context>) override {
    if (!frame->IsMain()) return;
    auto message = CefProcessMessage::Create("ikago.rendererPID");
    message->GetArgumentList()->SetInt(0, getpid());
    frame->SendProcessMessage(PID_BROWSER, message);
  }
 private:
  IMPLEMENT_REFCOUNTING(RendererIdentity);
};

int main(int argc, char* argv[]) {
  CefScopedSandboxContext sandbox;
  if (!sandbox.Initialize(argc, argv)) return 1;
  CefScopedLibraryLoader loader;
  if (!loader.LoadInHelper()) return 1;
  return CefExecuteProcess(CefMainArgs(argc, argv), new RendererIdentity(), nullptr);
}
