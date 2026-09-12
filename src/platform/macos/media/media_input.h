#pragma once

#include <string>

enum class MediaKind {
    Audio,
    Video,
    Unknown
};

MediaKind detect_media_kind(const std::string &path);

// For video, exports the audio track to a temporary .m4a file.
// For audio, returns the original path.
bool prepare_audio_source(
    const std::string &input_path,
    MediaKind kind,
    std::string &audio_path,
    std::string &temporary_path,
    std::string &error_message
);

void remove_temporary_file(const std::string &path);
