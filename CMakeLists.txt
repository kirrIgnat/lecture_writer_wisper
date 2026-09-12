cmake_minimum_required(VERSION 3.16)

project(
    LectureWhisper
    LANGUAGES C CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)

add_subdirectory(
    ../whisper.cpp
    whisper-build
)

# ---------------------------------------------------------------------------
# Platform-independent code
# ---------------------------------------------------------------------------

set(CORE_SOURCES
    src/core/transcriber.cpp
    src/core/frame_selector.cpp
)

set(OUTPUT_SOURCES
    src/output/bundle_writer.cpp
    src/output/pdf_writer.cpp
)

set(COMMON_SOURCES
    ${CORE_SOURCES}
    ${OUTPUT_SOURCES}
)

# ---------------------------------------------------------------------------
# Platform layer
#
# Future ports belong here:
#   src/platform/macos/
#   src/platform/windows/
#   src/platform/linux/
#
# Core transcription/output code above stays shared.
# ---------------------------------------------------------------------------

if(APPLE)
    enable_language(OBJCXX)

    set(PLATFORM_SOURCES
        src/platform/macos/app/main.mm
        src/platform/macos/app/AppDelegate.mm

        src/platform/macos/media/audio_decoder.cpp
        src/platform/macos/media/media_input.mm
        src/platform/macos/media/video_analyzer.mm
        src/platform/macos/media/ffmpeg_support.cpp
    )

    add_executable(
        LectureWhisperApp
        MACOSX_BUNDLE
        ${COMMON_SOURCES}
        ${PLATFORM_SOURCES}
    )

    target_include_directories(
        LectureWhisperApp
        PRIVATE
        src/core
        src/output
        src/platform/macos/app
        src/platform/macos/media
    )

    target_link_libraries(
        LectureWhisperApp
        PRIVATE
        whisper
        "-framework AppKit"
        "-framework AVFoundation"
        "-framework AudioToolbox"
        "-framework Foundation"
        "-framework CoreMedia"
        "-framework CoreGraphics"
        "-framework CoreFoundation"
        "-framework ImageIO"
    )

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/ffmpeg")
        set(
            FFMPEG_BINARY
            "${CMAKE_CURRENT_SOURCE_DIR}/tools/ffmpeg"
        )

        set_source_files_properties(
            "${FFMPEG_BINARY}"
            PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources"
            HEADER_FILE_ONLY TRUE
        )

        target_sources(
            LectureWhisperApp
            PRIVATE
            "${FFMPEG_BINARY}"
        )
    endif()

    set_target_properties(
        LectureWhisperApp
        PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "LectureWhisper"
        MACOSX_BUNDLE_GUI_IDENTIFIER "local.lecturewhisper.app"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "0.5"
        MACOSX_BUNDLE_BUNDLE_VERSION "5"
        OUTPUT_NAME "LectureWhisper"
    )
else()
    message(FATAL_ERROR
        "This source tree is ready for additional platform backends, "
        "but Windows/Linux UI and media backends have not been implemented yet."
    )
endif()
