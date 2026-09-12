#include "video_analyzer.h"
#include "frame_selector.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

namespace {

constexpr int kAnalysisWidth = 320;
constexpr int kAnalysisHeight = 180;

bool load_asset_duration(AVURLAsset *asset, double &seconds) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [asset loadValuesAsynchronouslyForKeys:@[@"duration"]
                         completionHandler:^{
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

#if !OS_OBJECT_USE_OBJC
    dispatch_release(sem);
#endif

    NSError *error = nil;
    const AVKeyValueStatus status =
        [asset statusOfValueForKey:@"duration" error:&error];

    if (status != AVKeyValueStatusLoaded) {
        if (error) {
            std::cerr << "AVFoundation duration error: "
                      << [[error description] UTF8String] << "\n";
        }
        return false;
    }

    seconds = CMTimeGetSeconds(asset.duration);
    return std::isfinite(seconds) && seconds > 0.0;
}

CGImageRef copy_image_at_seconds(
    AVAssetImageGenerator *generator,
    double seconds,
    CMTime *actual_time_out = nullptr
) {
    const CMTime requested =
        CMTimeMakeWithSeconds(std::max(0.0, seconds), 600);

    CMTime actual = kCMTimeZero;
    NSError *error = nil;

    CGImageRef image =
        [generator copyCGImageAtTime:requested
                         actualTime:&actual
                              error:&error];

    if (!image) {
        if (error) {
            std::cerr << "Frame extraction error at " << seconds << "s: "
                      << [[error description] UTF8String] << "\n";
        }
        return nullptr;
    }

    if (actual_time_out) {
        *actual_time_out = actual;
    }

    return image;
}

bool make_gray_320x180(
    CGImageRef image,
    std::vector<std::uint8_t> &gray
) {
    gray.assign(
        static_cast<std::size_t>(kAnalysisWidth) *
        static_cast<std::size_t>(kAnalysisHeight),
        0
    );

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceGray();
    if (!color_space) {
        return false;
    }

    CGContextRef ctx = CGBitmapContextCreate(
        gray.data(),
        kAnalysisWidth,
        kAnalysisHeight,
        8,
        kAnalysisWidth,
        color_space,
        kCGImageAlphaNone
    );

    CGColorSpaceRelease(color_space);

    if (!ctx) {
        return false;
    }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(
        ctx,
        CGRectMake(0, 0, kAnalysisWidth, kAnalysisHeight),
        image
    );
    CGContextRelease(ctx);
    return true;
}

std::string timestamp_filename(double seconds) {
    const int total =
        std::max(0, static_cast<int>(std::floor(seconds + 0.5)));

    const int h = total / 3600;
    const int m = (total % 3600) / 60;
    const int s = total % 60;

    std::ostringstream out;
    out << std::setfill('0')
        << std::setw(2) << h << "-"
        << std::setw(2) << m << "-"
        << std::setw(2) << s
        << ".jpg";
    return out.str();
}

bool save_jpeg(CGImageRef image, const std::string &path) {
    NSString *ns_path = [NSString stringWithUTF8String:path.c_str()];
    if (!ns_path) {
        return false;
    }

    NSURL *url = [NSURL fileURLWithPath:ns_path];

    CGImageDestinationRef dest =
        CGImageDestinationCreateWithURL(
            (CFURLRef)url,
            CFSTR("public.jpeg"),
            1,
            nullptr
        );

    if (!dest) {
        return false;
    }

    NSDictionary *properties = @{
        (NSString *)kCGImageDestinationLossyCompressionQuality : @0.90
    };

    CGImageDestinationAddImage(
        dest,
        image,
        (CFDictionaryRef)properties
    );

    const bool ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    return ok;
}

bool save_selected_frame(
    AVAssetImageGenerator *generator,
    double timestamp_seconds,
    const std::string &output_directory,
    std::string &saved_path
) {
    CGImageRef image =
        copy_image_at_seconds(generator, timestamp_seconds, nullptr);

    if (!image) {
        return false;
    }

    const std::filesystem::path path =
        std::filesystem::path(output_directory) /
        timestamp_filename(timestamp_seconds);

    const bool ok = save_jpeg(image, path.string());
    CGImageRelease(image);

    if (!ok) {
        return false;
    }

    saved_path = path.string();
    return true;
}

bool append_decision(
    const lecturewhisper::FrameDecision &decision,
    AVAssetImageGenerator *generator,
    const std::string &output_directory,
    VideoAnalysisResult &result
) {
    if (!decision.save) {
        return true;
    }

    std::string path;

    if (!save_selected_frame(
            generator,
            decision.timestamp_seconds,
            output_directory,
            path)) {
        return false;
    }

    VideoFrameInfo info;
    info.timestamp_seconds = decision.timestamp_seconds;
    info.image_path = path;
    info.difference = decision.change_score;

    result.frames.push_back(std::move(info));
    result.saved_frames = static_cast<int>(result.frames.size());
    return true;
}

} // namespace

bool analyze_video(
    const std::string &video_path,
    const std::string &output_directory,
    VideoAnalysisResult &result,
    double interval_seconds,
    double change_threshold
) {
    result = VideoAnalysisResult{};

    if (interval_seconds <= 0.0) {
        interval_seconds = 2.0;
    }

    std::error_code ec;
    std::filesystem::create_directories(output_directory, ec);

    if (ec) {
        std::cerr << "Cannot create frames directory: "
                  << ec.message() << "\n";
        return false;
    }

    @autoreleasepool {
        NSString *input =
            [NSString stringWithUTF8String:video_path.c_str()];

        if (!input) {
            return false;
        }

        NSURL *url = [NSURL fileURLWithPath:input];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];

        double duration = 0.0;
        if (!load_asset_duration(asset, duration)) {
            std::cerr << "Не удалось определить длительность видео.\n";
            return false;
        }

        result.duration_seconds = duration;

        AVAssetImageGenerator *generator =
            [[[AVAssetImageGenerator alloc] initWithAsset:asset] autorelease];

        generator.appliesPreferredTrackTransform = YES;
        generator.requestedTimeToleranceBefore =
            CMTimeMakeWithSeconds(0.15, 600);
        generator.requestedTimeToleranceAfter =
            CMTimeMakeWithSeconds(0.15, 600);

        lecturewhisper::FrameSelectorConfig config;
        if (change_threshold > 0.0) {
            config.global_change_mad = change_threshold;
        }

        lecturewhisper::FrameSelector selector(config);

        for (double requested = 0.0;
             requested <= duration;
             requested += interval_seconds) {

            @autoreleasepool {
                CMTime actual_time = kCMTimeZero;
                CGImageRef image = copy_image_at_seconds(
                    generator,
                    requested,
                    &actual_time
                );

                if (!image) {
                    continue;
                }

                std::vector<std::uint8_t> gray;
                if (!make_gray_320x180(image, gray)) {
                    CGImageRelease(image);
                    continue;
                }

                CGImageRelease(image);

                const double actual_seconds =
                    CMTimeGetSeconds(actual_time);

                lecturewhisper::GrayFrameView frame;
                frame.pixels = gray.data();
                frame.width = kAnalysisWidth;
                frame.height = kAnalysisHeight;
                frame.stride = kAnalysisWidth;
                frame.timestamp_seconds =
                    std::isfinite(actual_seconds)
                        ? actual_seconds
                        : requested;

                ++result.checked_frames;

                const auto decision = selector.process(frame);

                if (!append_decision(
                        decision,
                        generator,
                        output_directory,
                        result)) {
                    return false;
                }
            }
        }

        const auto final_decision = selector.finalize();

        if (!append_decision(
                final_decision,
                generator,
                output_directory,
                result)) {
            return false;
        }
    }

    return true;
}
