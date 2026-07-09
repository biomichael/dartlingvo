#ifndef LSD_C_WRAPPER_H
#define LSD_C_WRAPPER_H

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

EXPORT int decode_lsd(const char* inputPath, const char* outputPath);

EXPORT int get_last_error(char* buffer, int bufferSize);

#endif
