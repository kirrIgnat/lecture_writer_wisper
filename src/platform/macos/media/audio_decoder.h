#pragma once
#include <string>
#include <vector>

struct AudioData {
    std::vector<float> samples;
    double duration_seconds = 0.0;
};

bool decode_audio(const std::string &path, AudioData &audio);
