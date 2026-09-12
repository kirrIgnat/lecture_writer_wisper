#pragma once

#include "transcriber.h"
#include "video_analyzer.h"

#include <string>

bool write_video_context_markdown(
    const std::string &path,
    const TranscriptionResult &transcript,
    const VideoAnalysisResult &video
);
