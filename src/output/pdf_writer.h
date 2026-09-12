#pragma once

#include <string>

bool create_frames_pdf(
    const std::string &frames_directory,
    const std::string &output_pdf,
    std::string &error_message
);
