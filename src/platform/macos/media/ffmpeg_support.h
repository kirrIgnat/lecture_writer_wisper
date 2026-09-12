#pragma once

#include "video_analyzer.h"

#include <string>

// Finds ffmpeg in the app bundle, project tools directory, common install paths, or PATH.
std::string find_ffmpeg_binary();

bool ffmpeg_available();

// Decode any ffmpeg-supported media file to 16 kHz mono WAV for Whisper.
bool ffmpeg_extract_audio_16k_mono(
    const std::string &input_path,
    const std::string &output_wav_path,
    std::string &error_message
);

// Fallback video analysis for formats AVFoundation cannot decode (e.g. WebM on Catalina).
// ffmpeg samples one full-resolution frame every interval_seconds, then this function
// keeps only frames whose visual difference crosses change_threshold.
bool analyze_video_with_ffmpeg(
    const std::string &video_path,
    const std::string &output_directory,
    VideoAnalysisResult &result,
    double interval_seconds,
    double change_threshold,
    std::string &error_message
);
