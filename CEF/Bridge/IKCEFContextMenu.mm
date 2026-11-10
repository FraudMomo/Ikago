#import "IKCEFPageInternal.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_menu_model.h"

namespace {
constexpr int kInspect = MENU_ID_USER_FIRST + 100;
class ContextMenu final : public CefContextMenuHandler {
 public:
  explicit ContextMenu(IKCEFPage *page) : page_(page) {}
  void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
      CefRefPtr<CefContextMenuParams>, CefRefPtr<CefMenuModel> model) override {
    IKCEFPage *page = page_;
    if (!page || page.isClosed || !page->_developerTools) return;
    if (model->GetCount()) model->AddSeparator();
    model->AddItem(kInspect, "Inspect Element");
  }
  bool OnContextMenuCommand(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
      CefRefPtr<CefContextMenuParams> params, int command, EventFlags) override {
    if (command != kInspect) return false;
    IKCEFPage *page = page_;
    if (page && !page.isClosed && page->_developerTools)
      [page inspectAtPoint:NSMakePoint(params->GetXCoord(), params->GetYCoord())];
    return true;
  }
 private:
  __weak IKCEFPage *page_;
  IMPLEMENT_REFCOUNTING(ContextMenu);
};
}
CefRefPtr<CefContextMenuHandler> IKCEFMakeContextMenu(IKCEFPage *page) { return new ContextMenu(page); }
