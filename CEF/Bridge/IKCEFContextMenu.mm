#import "IKCEFPageInternal.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_menu_model.h"

namespace {
constexpr int kPrivate = MENU_ID_USER_FIRST + 101;
constexpr int kSearch = MENU_ID_USER_FIRST + 102;
constexpr int kTranslate = MENU_ID_USER_FIRST + 103;
constexpr int kVideo = MENU_ID_USER_FIRST + 104;
constexpr int kSave = MENU_ID_USER_FIRST + 105;
constexpr int kInspect = MENU_ID_USER_FIRST + 100;
class ContextMenu final : public CefContextMenuHandler {
 public:
  explicit ContextMenu(IKCEFPage *page) : page_(page) {}
  void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
      CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model) override {
    IKCEFPage *page = page_;
    if (!page || page.isClosed) return;
    if (model->GetCount()) model->AddSeparator();
    if (!params->GetLinkUrl().empty()) model->AddItem(kPrivate, "Open Link in Private Window");
    if (!params->GetSelectionText().empty()) model->AddItem(kSearch, "Search Selection in Ikago");
    model->AddItem(kTranslate, "Translate Page");
    model->AddItem(kSave, "Save Page As…");
    if (params->GetMediaType() == CM_MEDIATYPE_VIDEO) {
      // Ikago's own panel (ChromiumPictureInPicture) floats any video Chromium plays, streams included.
      model->AddItem(kVideo, "Picture in Picture");
    }
    if (!page->_developerTools) return;
    if (model->GetCount()) model->AddSeparator();
    model->AddItem(kInspect, "Inspect Element");
  }
  bool OnContextMenuCommand(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
      CefRefPtr<CefContextMenuParams> params, int command, EventFlags) override {
    IKCEFPage *page = page_;
    if (page && !page.isClosed && command >= kPrivate && command <= kSave) {
      NSString *action = command == kPrivate ? @"private" : command == kSearch ? @"search" : command == kVideo ? @"video" : command == kSave ? @"save" : @"translate";
      std::string value = command == kPrivate ? params->GetLinkUrl().ToString() : command == kSearch ? params->GetSelectionText().ToString() : command == kVideo ? params->GetSourceUrl().ToString() : "";
      [page emit:@"contextAction" payload:@{@"action": action, @"text": [NSString stringWithUTF8String:value.c_str()] ?: @""}];
      return true;
    }
    if (command != kInspect) return false;
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
