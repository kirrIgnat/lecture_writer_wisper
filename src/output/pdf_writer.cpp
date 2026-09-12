#include "pdf_writer.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static CFStringRef make_cf_string(const std::string &text) {
    return CFStringCreateWithCString(
        kCFAllocatorDefault,
        text.c_str(),
        kCFStringEncodingUTF8
    );
}

static CFURLRef make_file_url(const std::string &path) {
    CFStringRef str = make_cf_string(path);
    if (!str) {
        return nullptr;
    }

    CFURLRef url = CFURLCreateWithFileSystemPath(
        kCFAllocatorDefault,
        str,
        kCFURLPOSIXPathStyle,
        false
    );

    CFRelease(str);
    return url;
}

static CGImageRef load_image(const std::string &path) {
    CFURLRef url = make_file_url(path);
    if (!url) {
        return nullptr;
    }

    CGImageSourceRef source = CGImageSourceCreateWithURL(url, nullptr);
    CFRelease(url);

    if (!source) {
        return nullptr;
    }

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);

    return image;
}

bool create_frames_pdf(
    const std::string &frames_directory,
    const std::string &output_pdf,
    std::string &error_message
) {
    error_message.clear();

    std::error_code ec;

    if (!fs::exists(frames_directory, ec) ||
        !fs::is_directory(frames_directory, ec)) {
        error_message = "Папка с кадрами не найдена";
        return false;
    }

    std::vector<fs::path> files;

    for (const auto &entry : fs::directory_iterator(frames_directory)) {
        if (!entry.is_regular_file()) {
            continue;
        }

        std::string ext = entry.path().extension().string();

        std::transform(
            ext.begin(),
            ext.end(),
            ext.begin(),
            [](unsigned char c) {
                return static_cast<char>(std::tolower(c));
            }
        );

        if (ext == ".jpg" || ext == ".jpeg" || ext == ".png") {
            files.push_back(entry.path());
        }
    }

    if (files.empty()) {
        error_message = "В папке frames нет изображений";
        return false;
    }

    std::sort(files.begin(), files.end());

    CFURLRef pdfURL = make_file_url(output_pdf);

    if (!pdfURL) {
        error_message = "Не удалось создать URL для PDF";
        return false;
    }

    CGRect pageRect = CGRectMake(0, 0, 595, 842);

    CGContextRef pdf = CGPDFContextCreateWithURL(
        pdfURL,
        &pageRect,
        nullptr
    );

    CFRelease(pdfURL);

    if (!pdf) {
        error_message = "Не удалось создать PDF";
        return false;
    }

    const CGFloat margin = 35.0;
    const CGFloat titleHeight = 45.0;
    int addedPages = 0;

    for (const fs::path &file : files) {
        CGImageRef image = load_image(file.string());

        if (!image) {
            continue;
        }

        CGPDFContextBeginPage(pdf, nullptr);

        CGContextSetRGBFillColor(pdf, 0, 0, 0, 1);
        CGContextSelectFont(
            pdf,
            "Helvetica-Bold",
            16,
            kCGEncodingMacRoman
        );
        CGContextSetTextDrawingMode(pdf, kCGTextFill);

        const std::string title = file.filename().string();

        CGContextShowTextAtPoint(
            pdf,
            margin,
            pageRect.size.height - margin,
            title.c_str(),
            title.size()
        );

        const CGFloat imageWidth =
            static_cast<CGFloat>(CGImageGetWidth(image));

        const CGFloat imageHeight =
            static_cast<CGFloat>(CGImageGetHeight(image));

        const CGFloat availableWidth =
            pageRect.size.width - margin * 2.0;

        const CGFloat availableHeight =
            pageRect.size.height - margin * 2.0 - titleHeight;

        const CGFloat scaleX = availableWidth / imageWidth;
        const CGFloat scaleY = availableHeight / imageHeight;
        const CGFloat scale = std::min(scaleX, scaleY);

        const CGFloat drawWidth = imageWidth * scale;
        const CGFloat drawHeight = imageHeight * scale;

        const CGFloat x =
            (pageRect.size.width - drawWidth) / 2.0;

        const CGFloat y =
            margin + (availableHeight - drawHeight) / 2.0;

        CGRect imageRect = CGRectMake(
            x,
            y,
            drawWidth,
            drawHeight
        );

        CGContextDrawImage(pdf, imageRect, image);

        CGPDFContextEndPage(pdf);
        CGImageRelease(image);

        ++addedPages;
    }

    CGPDFContextClose(pdf);
    CGContextRelease(pdf);

    if (addedPages == 0) {
        error_message = "Не удалось добавить изображения в PDF";
        return false;
    }

    return true;
}
