#pragma once

#include <string>
#include <vector>

struct VideoFrameInfo {
    double timestamp_seconds = 0.0;
    std::string image_path;
    double difference = 0.0;
};

struct VideoAnalysisResult {
    double duration_seconds = 0.0;
    int checked_frames = 0;
    int saved_frames = 0;
    std::vector<VideoFrameInfo> frames;
};

bool analyze_video(
    const std::string &video_path,
    const std::string &output_directory,
    VideoAnalysisResult &result,
    double interval_seconds = 2.0,
    double change_threshold = 10.0
);
