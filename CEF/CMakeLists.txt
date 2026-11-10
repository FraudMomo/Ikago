# Builds the public CEF bridge and sandboxed helper against the pinned prebuilt SDK (cef-lock.json).
# The Swift app is compiled separately by scripts/build.py. Never build Chromium itself.
cmake_minimum_required(VERSION 3.24)
project(IkagoCEF LANGUAGES C CXX OBJCXX)

if(NOT APPLE OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  message(FATAL_ERROR "The pinned CEF SDK targets macOS ARM64 only")
endif()

set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.cef/distribution")
set(PROJECT_ARCH arm64)
set(USE_SANDBOX ON CACHE BOOL "Sandboxed helper processes" FORCE)
list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)
add_subdirectory("${CEF_LIBCEF_DLL_WRAPPER_PATH}" libcef_dll_wrapper)
target_compile_definitions(libcef_dll_wrapper PRIVATE CEF_API_VERSION=15600)

set(BRIDGE "${CMAKE_CURRENT_SOURCE_DIR}/Bridge")
add_library(IKCEFBridge STATIC
  "${BRIDGE}/IKCEFAudio.mm"
  "${BRIDGE}/IKCEFClient.mm"
  "${BRIDGE}/IKCEFContextMenu.mm"
  "${BRIDGE}/IKCEFContexts.mm"
  "${BRIDGE}/IKCEFDownloads.mm"
  "${BRIDGE}/IKCEFInspectorClient.mm"
  "${BRIDGE}/IKCEFMediaRequest.mm"
  "${BRIDGE}/IKCEFNativeTools.mm"
  "${BRIDGE}/IKCEFPage.mm"
  "${BRIDGE}/IKCEFPage+DeveloperTools.mm"
  "${BRIDGE}/IKCEFPage+DevTools.mm"
  "${BRIDGE}/IKCEFRuntime.mm"
  "${BRIDGE}/IKCEFSecurity.mm"
  "${BRIDGE}/IKAV1Encoder.mm"
  "${BRIDGE}/IKCEFMediaBridge.mm"
)
target_include_directories(IKCEFBridge PUBLIC "${BRIDGE}" PRIVATE "${CEF_ROOT}")
target_compile_features(IKCEFBridge PRIVATE cxx_std_20)
target_compile_options(IKCEFBridge PRIVATE -fobjc-arc)
target_compile_definitions(IKCEFBridge PRIVATE CEF_API_VERSION=15600)
set_target_properties(IKCEFBridge PROPERTIES OSX_DEPLOYMENT_TARGET "26.0")
# SVT-AV1 (pinned in svtav1-lock.json, built by scripts/build.py) for the media translation layer.
set(SVTAV1 "${CMAKE_CURRENT_SOURCE_DIR}/../out/svtav1/install")
target_include_directories(IKCEFBridge PRIVATE "${SVTAV1}/include/svt-av1")
target_link_libraries(IKCEFBridge PUBLIC libcef_dll_wrapper "-framework AppKit" "${SVTAV1}/lib/libSvtAv1Enc.a")

# IKCEFHelper.cc has its own main(); packaging copies this binary into each helper app.
add_executable(IkagoHelper "${BRIDGE}/IKCEFHelper.cc")
target_include_directories(IkagoHelper PRIVATE "${CEF_ROOT}")
target_compile_features(IkagoHelper PRIVATE cxx_std_20)
target_compile_definitions(IkagoHelper PRIVATE CEF_API_VERSION=15600)
target_link_libraries(IkagoHelper PRIVATE libcef_dll_wrapper "-framework AppKit")
