#include "include/cef_audio_handler.h"

/// One handler serves every page; streams are keyed by CEF browser identifier.
CefRefPtr<CefAudioHandler> IKCEFMakeAudioHandler();
/// Ikago's mute for a page applies to the sound Ikago plays for it.
void IKCEFSetAudioMuted(int browserID, bool muted);
