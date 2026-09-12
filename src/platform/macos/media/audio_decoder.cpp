#include "audio_decoder.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <iostream>
#include <vector>
#include <string>

namespace {
void print_osstatus(const char *where, OSStatus status) {
    char str[5] = {};
    UInt32 value = static_cast<UInt32>(status);
    str[0] = static_cast<char>((value >> 24) & 0xFF);
    str[1] = static_cast<char>((value >> 16) & 0xFF);
    str[2] = static_cast<char>((value >> 8) & 0xFF);
    str[3] = static_cast<char>(value & 0xFF);
    bool printable = str[0] >= 32 && str[0] <= 126 && str[1] >= 32 && str[1] <= 126 && str[2] >= 32 && str[2] <= 126 && str[3] >= 32 && str[3] <= 126;
    std::cerr << where << " failed: ";
    if (printable) std::cerr << "'" << str << "'";
    else std::cerr << status;
    std::cerr << "\n";
}
}

bool decode_audio(const std::string &path, AudioData &audio) {
    audio.samples.clear();
    audio.duration_seconds = 0.0;

    CFStringRef path_string = CFStringCreateWithCString(kCFAllocatorDefault, path.c_str(), kCFStringEncodingUTF8);
    if (!path_string) {
        std::cerr << "Не удалось создать путь к файлу\n";
        return false;
    }
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path_string, kCFURLPOSIXPathStyle, false);
    CFRelease(path_string);
    if (!url) {
        std::cerr << "Не удалось создать URL для файла\n";
        return false;
    }

    ExtAudioFileRef file = nullptr;
    OSStatus status = ExtAudioFileOpenURL(url, &file);
    CFRelease(url);
    if (status != noErr) {
        print_osstatus("ExtAudioFileOpenURL", status);
        return false;
    }

    AudioStreamBasicDescription source_format {};
    UInt32 size = sizeof(source_format);
    status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source_format);
    if (status != noErr) {
        print_osstatus("kExtAudioFileProperty_FileDataFormat", status);
        ExtAudioFileDispose(file);
        return false;
    }

    SInt64 source_frames = 0;
    size = sizeof(source_frames);
    status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &source_frames);
    if (status == noErr && source_format.mSampleRate > 0.0) {
        audio.duration_seconds = static_cast<double>(source_frames) / source_format.mSampleRate;
    }

    AudioStreamBasicDescription client_format {};
    client_format.mSampleRate = 16000.0;
    client_format.mFormatID = kAudioFormatLinearPCM;
    client_format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    client_format.mBytesPerPacket = sizeof(float);
    client_format.mFramesPerPacket = 1;
    client_format.mBytesPerFrame = sizeof(float);
    client_format.mChannelsPerFrame = 1;
    client_format.mBitsPerChannel = 32;

    status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(client_format), &client_format);
    if (status != noErr) {
        print_osstatus("kExtAudioFileProperty_ClientDataFormat", status);
        ExtAudioFileDispose(file);
        return false;
    }

    constexpr UInt32 BUFFER_FRAMES = 16384;
    std::vector<float> buffer(BUFFER_FRAMES);
    if (audio.duration_seconds > 0.0) {
        audio.samples.reserve(static_cast<size_t>(audio.duration_seconds * 16000.0));
    }

    while (true) {
        UInt32 frames_to_read = BUFFER_FRAMES;
        AudioBufferList buffer_list {};
        buffer_list.mNumberBuffers = 1;
        buffer_list.mBuffers[0].mNumberChannels = 1;
        buffer_list.mBuffers[0].mDataByteSize = BUFFER_FRAMES * sizeof(float);
        buffer_list.mBuffers[0].mData = buffer.data();
        status = ExtAudioFileRead(file, &frames_to_read, &buffer_list);
        if (status != noErr) {
            print_osstatus("ExtAudioFileRead", status);
            ExtAudioFileDispose(file);
            return false;
        }
        if (frames_to_read == 0) break;
        audio.samples.insert(audio.samples.end(), buffer.begin(), buffer.begin() + frames_to_read);
    }

    ExtAudioFileDispose(file);
    if (audio.samples.empty()) {
        std::cerr << "После декодирования нет аудиоданных\n";
        return false;
    }
    audio.duration_seconds = static_cast<double>(audio.samples.size()) / 16000.0;
    return true;
}
