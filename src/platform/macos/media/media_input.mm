#include "media_input.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <string>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

namespace fs = std::filesystem;

// ------------------------------------------------------------
// Вспомогательные функции
// ------------------------------------------------------------

static std::string lower_ext(const std::string &path) {
    std::string ext = fs::path(path).extension().string();

    std::transform(
        ext.begin(),
        ext.end(),
        ext.begin(),
        [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        }
    );

    return ext;
}

static std::string shell_quote(const std::string &value) {
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

static std::string find_ffmpeg() {
#ifdef __APPLE__
    char executable_buffer[4096];
    uint32_t executable_size =
        static_cast<uint32_t>(sizeof(executable_buffer));

    if (
        _NSGetExecutablePath(
            executable_buffer,
            &executable_size
        ) == 0
    ) {
        fs::path executable_path(executable_buffer);

        fs::path bundled_ffmpeg =
            executable_path
                .parent_path()
                .parent_path()
                / "Resources"
                / "ffmpeg";

        if (
            fs::exists(bundled_ffmpeg) &&
            fs::is_regular_file(bundled_ffmpeg)
        ) {
            return bundled_ffmpeg.string();
        }
    }
#endif

    const char *possible_paths[] = {
        "tools/ffmpeg",
        "./tools/ffmpeg",
        "../tools/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
        "/opt/homebrew/bin/ffmpeg"
    };

    for (const char *path : possible_paths) {
        if (
            fs::exists(path) &&
            fs::is_regular_file(path)
        ) {
            return path;
        }
    }

    return "";
}

static bool extract_audio_with_ffmpeg(
    const std::string &input_path,
    std::string &audio_path,
    std::string &temporary_path,
    std::string &error_message
) {
    const std::string ffmpeg =
        find_ffmpeg();

    if (ffmpeg.empty()) {
        error_message =
            "FFmpeg не найден. "
            "Проверьте LectureWhisper.app/Contents/Resources/ffmpeg";
        return false;
    }

    NSString *tmpDir =
        NSTemporaryDirectory();

    NSString *name =
        [NSString stringWithFormat:
            @"LectureWhisper-%@.wav",
            [[NSUUID UUID] UUIDString]
        ];

    NSString *tmpPath =
        [tmpDir stringByAppendingPathComponent:name];

    const std::string output_path =
        [tmpPath UTF8String];

    std::string command =
        shell_quote(ffmpeg) +
        " -hide_banner"
        " -loglevel error"
        " -y"
        " -i " +
        shell_quote(input_path) +
        " -vn"
        " -ac 1"
        " -ar 16000"
        " -c:a pcm_s16le " +
        shell_quote(output_path);

    const int result =
        std::system(command.c_str());

    if (result != 0) {
        error_message =
            "FFmpeg не смог извлечь аудио из видео";
        return false;
    }

    std::error_code ec;

    if (
        !fs::exists(output_path, ec) ||
        ec
    ) {
        error_message =
            "FFmpeg завершился, но временный WAV не найден";
        return false;
    }

    const auto size =
        fs::file_size(output_path, ec);

    if (
        ec ||
        size == 0
    ) {
        error_message =
            "FFmpeg создал пустой аудиофайл";
        return false;
    }

    temporary_path =
        output_path;

    audio_path =
        output_path;

    return true;
}

// ------------------------------------------------------------
// Определение типа медиа
// ------------------------------------------------------------

MediaKind detect_media_kind(
    const std::string &path
) {
    const std::string ext =
        lower_ext(path);

    if (
        ext == ".mp4" ||
        ext == ".mov" ||
        ext == ".m4v" ||
        ext == ".webm" ||
        ext == ".mkv"
    ) {
        return MediaKind::Video;
    }

    if (
        ext == ".wav" ||
        ext == ".m4a" ||
        ext == ".mp3" ||
        ext == ".aac" ||
        ext == ".aif" ||
        ext == ".aiff" ||
        ext == ".caf"
    ) {
        return MediaKind::Audio;
    }

    return MediaKind::Unknown;
}

// ------------------------------------------------------------
// Подготовка аудио для Whisper
// ------------------------------------------------------------

bool prepare_audio_source(
    const std::string &input_path,
    MediaKind kind,
    std::string &audio_path,
    std::string &temporary_path,
    std::string &error_message
) {
    @autoreleasepool {

        audio_path.clear();
        temporary_path.clear();
        error_message.clear();

        // ----------------------------------------------------
        // Обычный аудиофайл
        // ----------------------------------------------------

        if (kind == MediaKind::Audio) {
            audio_path =
                input_path;

            return true;
        }

        if (kind != MediaKind::Video) {
            error_message =
                "Неподдерживаемый тип файла";

            return false;
        }

        const std::string ext =
            lower_ext(input_path);

        // ----------------------------------------------------
        // WebM / MKV:
        //
        // Catalina AVFoundation может не понимать контейнер
        // или Opus/Vorbis внутри него, поэтому сразу FFmpeg.
        // ----------------------------------------------------

        if (
            ext == ".webm" ||
            ext == ".mkv"
        ) {
            return extract_audio_with_ffmpeg(
                input_path,
                audio_path,
                temporary_path,
                error_message
            );
        }

        // ----------------------------------------------------
        // MP4 / MOV / M4V:
        // сначала используем штатный AVFoundation.
        // ----------------------------------------------------

        NSString *input =
            [NSString
                stringWithUTF8String:
                    input_path.c_str()
            ];

        if (!input) {
            error_message =
                "Не удалось преобразовать путь к видео";

            return false;
        }

        NSURL *inputURL =
            [NSURL fileURLWithPath:input];

        AVURLAsset *asset =
            [AVURLAsset
                URLAssetWithURL:inputURL
                options:nil
            ];

        NSArray *audioTracks =
            [asset
                tracksWithMediaType:
                    AVMediaTypeAudio
            ];

        // Если Catalina не смогла увидеть дорожку,
        // пробуем FFmpeg.
        if ([audioTracks count] == 0) {
            return extract_audio_with_ffmpeg(
                input_path,
                audio_path,
                temporary_path,
                error_message
            );
        }

        // ----------------------------------------------------
        // Создаём временный M4A через AVFoundation
        // ----------------------------------------------------

        NSString *tmpDir =
            NSTemporaryDirectory();

        NSString *name =
            [NSString stringWithFormat:
                @"LectureWhisper-%@.m4a",
                [[NSUUID UUID] UUIDString]
            ];

        NSString *tmpPath =
            [tmpDir
                stringByAppendingPathComponent:
                    name
            ];

        NSURL *outputURL =
            [NSURL fileURLWithPath:tmpPath];

        AVAssetExportSession *session =
            [[AVAssetExportSession alloc]
                initWithAsset:asset
                presetName:
                    AVAssetExportPresetAppleM4A
            ];

        // Если нативный экспорт создать нельзя,
        // пробуем FFmpeg.
        if (!session) {
            return extract_audio_with_ffmpeg(
                input_path,
                audio_path,
                temporary_path,
                error_message
            );
        }

        session.outputURL =
            outputURL;

        session.outputFileType =
            AVFileTypeAppleM4A;

        session.shouldOptimizeForNetworkUse =
            NO;

        dispatch_semaphore_t sem =
            dispatch_semaphore_create(0);

        [session
            exportAsynchronouslyWithCompletionHandler:^{

                dispatch_semaphore_signal(sem);
            }
        ];

        dispatch_semaphore_wait(
            sem,
            DISPATCH_TIME_FOREVER
        );

        const AVAssetExportSessionStatus status =
            session.status;

        [session release];

#if !OS_OBJECT_USE_OBJC
        dispatch_release(sem);
#endif

        // Если AVFoundation не справился,
        // снова пробуем FFmpeg.
        if (
            status !=
            AVAssetExportSessionStatusCompleted
        ) {
            return extract_audio_with_ffmpeg(
                input_path,
                audio_path,
                temporary_path,
                error_message
            );
        }

        temporary_path =
            [tmpPath UTF8String];

        audio_path =
            temporary_path;

        return true;
    }
}

// ------------------------------------------------------------
// Удаление временного аудиофайла
// ------------------------------------------------------------

void remove_temporary_file(
    const std::string &path
) {
    if (path.empty()) {
        return;
    }

    std::error_code ec;

    fs::remove(
        path,
        ec
    );
}