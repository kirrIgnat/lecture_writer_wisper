#include "ffmpeg_support.h"

#include <cstdlib>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <string>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
namespace fs = std::filesystem;

namespace {

std::string shell_quote(const std::string &value) {
    std::string result = "'";

    for (char c : value) {
        if (c == '\'') {
            result += "'\\''";
        } else {
            result += c;
        }
    }

    result += "'";
    return result;
}

std::string format_timestamp(double seconds) {
    int total = static_cast<int>(seconds);

    int hours = total / 3600;
    int minutes = (total % 3600) / 60;
    int secs = total % 60;

    std::ostringstream out;

    out
        << std::setfill('0')
        << std::setw(2) << hours << "-"
        << std::setw(2) << minutes << "-"
        << std::setw(2) << secs;

    return out.str();
}

}

bool analyze_video_with_ffmpeg(
    const std::string &video_path,
    const std::string &output_directory,
    VideoAnalysisResult &result,
    double interval_seconds,
    double change_threshold,
    std::string &error_message
) {
    result = {};
    error_message.clear();

    if (interval_seconds <= 0.0) {
        error_message = "Некорректный интервал анализа видео";
        return false;
    }

    std::error_code ec;

    fs::create_directories(
        output_directory,
        ec
    );

    if (ec) {
        error_message =
            "Не удалось создать папку кадров: " +
            output_directory;

        return false;
    }

    // --------------------------------------------------------
    // Ищем ffmpeg
    // --------------------------------------------------------

    std::string ffmpeg_path;

    const char *possible_paths[] = {
        "tools/ffmpeg",
        "./tools/ffmpeg",
        "/usr/local/bin/ffmpeg"
    };

    for (const char *path : possible_paths) {
        if (
            fs::exists(path) &&
            fs::is_regular_file(path)
        ) {
            ffmpeg_path = path;
            break;
        }
    }

    // Если запускаемся из .app, ffmpeg должен лежать здесь.
    if (ffmpeg_path.empty()) {
        fs::path executable =
            fs::read_symlink(
                "/proc/self/exe",
                ec
            );

        (void) executable;
    }

    // На macOS проще дополнительно проверить bundle-путь
    // относительно текущего executable через _NSGetExecutablePath.

#ifdef __APPLE__

    if (ffmpeg_path.empty()) {
        char executable_buffer[4096];
        uint32_t executable_size =
            sizeof(executable_buffer);


        if (
            _NSGetExecutablePath(
                executable_buffer,
                &executable_size
            ) == 0
        ) {
            fs::path executable_path(
                executable_buffer
            );

            fs::path bundled_ffmpeg =
                executable_path
                    .parent_path()
                    .parent_path()
                    / "Resources"
                    / "ffmpeg";

            if (fs::exists(bundled_ffmpeg)) {
                ffmpeg_path =
                    bundled_ffmpeg.string();
            }
        }
    }

#endif

    if (ffmpeg_path.empty()) {
        // Последняя попытка — PATH.
        int status =
            std::system(
                "command -v ffmpeg >/dev/null 2>&1"
            );

        if (status == 0) {
            ffmpeg_path = "ffmpeg";
        }
    }

    if (ffmpeg_path.empty()) {
        error_message =
            "ffmpeg не найден. "
            "Положите его в tools/ffmpeg "
            "или внутрь LectureWhisper.app/Contents/Resources/";

        return false;
    }

    // --------------------------------------------------------
    // Для WebM fallback пока извлекаем один кадр каждые N секунд.
    //
    // Это намеренно простой и надёжный вариант.
    // Позже можно добавить такой же pixel-diff, как для AVFoundation.
    // --------------------------------------------------------

    fs::path temporary_pattern =
        fs::path(output_directory) /
        "frame_%06d.jpg";

    std::ostringstream command;

    command
        << shell_quote(ffmpeg_path)
        << " -hide_banner -loglevel error"
        << " -y"
        << " -i "
        << shell_quote(video_path)
        << " -vf "
        << shell_quote(
            "fps=1/" +
            std::to_string(interval_seconds)
        )
        << " -q:v 2 "
        << shell_quote(
            temporary_pattern.string()
        );

    int status =
        std::system(
            command.str().c_str()
        );

    if (status != 0) {
        error_message =
            "ffmpeg не смог извлечь кадры из видео";

        return false;
    }

    // --------------------------------------------------------
    // Переименовываем кадры по таймкодам.
    // --------------------------------------------------------

    int frame_index = 0;

    for (
        int index = 1;
        ;
        ++index
    ) {
        std::ostringstream filename;

        filename
            << "frame_"
            << std::setfill('0')
            << std::setw(6)
            << index
            << ".jpg";

        fs::path source =
            fs::path(output_directory) /
            filename.str();

        if (!fs::exists(source)) {
            break;
        }

        double timestamp =
            static_cast<double>(frame_index) *
            interval_seconds;

        fs::path destination =
            fs::path(output_directory) /
            (
                format_timestamp(timestamp) +
                ".jpg"
            );

        std::error_code rename_error;

        fs::rename(
            source,
            destination,
            rename_error
        );

        if (rename_error) {
            error_message =
                "Не удалось переименовать кадр: " +
                source.string();

            return false;
        }

        VideoFrameInfo info;

        info.timestamp_seconds =
            timestamp;

        info.image_path =
            destination.string();

        // Для FFmpeg fallback сейчас точное значение
        // pixel difference не вычисляется.
        info.difference =
            change_threshold;

        result.frames.push_back(info);

        ++result.checked_frames;
        ++result.saved_frames;
        ++frame_index;
    }

    if (result.saved_frames == 0) {
        error_message =
            "ffmpeg не извлёк ни одного кадра";

        return false;
    }

    result.duration_seconds =
        static_cast<double>(
            result.saved_frames
        ) *
        interval_seconds;

    return true;
}