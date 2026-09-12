#include "bundle_writer.h"

#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace fs = std::filesystem;

static std::string stamp(int ms) {
    int total = ms / 1000;
    int h = total / 3600;
    int m = (total % 3600) / 60;
    int s = total % 60;
    std::ostringstream out;
    out << std::setfill('0') << std::setw(2) << h << ":"
        << std::setw(2) << m << ":" << std::setw(2) << s;
    return out.str();
}

bool write_video_context_markdown(
    const std::string &path,
    const TranscriptionResult &transcript,
    const VideoAnalysisResult &video
) {
    std::ofstream out(path);
    if (!out) return false;

    out << "# Lecture context\n\n";
    out << "Текст и ключевые кадры синхронизированы по таймкодам.\n\n";

    size_t frameIndex = 0;

    for (const auto &seg : transcript.segments) {
        out << "## [" << stamp(seg.start_ms) << " - " << stamp(seg.end_ms) << "]\n\n";
        out << seg.text << "\n\n";

        const double start = seg.start_ms / 1000.0;
        const double end = seg.end_ms / 1000.0;
        bool wroteFrame = false;

        while (frameIndex < video.frames.size() &&
               video.frames[frameIndex].timestamp_seconds < start) {
            ++frameIndex;
        }

        size_t j = frameIndex;
        while (j < video.frames.size() &&
               video.frames[j].timestamp_seconds <= end) {
            fs::path p(video.frames[j].image_path);
            out << "- Кадр: `" << p.filename().string() << "`\n";
            wroteFrame = true;
            ++j;
        }

        if (wroteFrame) out << "\n";
    }

    return true;
}
