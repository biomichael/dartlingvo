#include "lsd_c_wrapper.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

static char lastError[4096] = {0};

static void setError(const char* msg) {
    strncpy(lastError, msg, sizeof(lastError) - 1);
    lastError[sizeof(lastError) - 1] = '\0';
}

static void writeUtf8(FILE* out, uint32_t cp) {
    if (cp < 0x80) {
        fputc((int)cp, out);
    } else if (cp < 0x800) {
        fputc(0xC0 | (cp >> 6), out);
        fputc(0x80 | (cp & 0x3F), out);
    } else if (cp < 0x10000) {
        fputc(0xE0 | (cp >> 12), out);
        fputc(0x80 | ((cp >> 6) & 0x3F), out);
        fputc(0x80 | (cp & 0x3F), out);
    } else {
        fputc(0xF0 | (cp >> 18), out);
        fputc(0x80 | ((cp >> 12) & 0x3F), out);
        fputc(0x80 | ((cp >> 6) & 0x3F), out);
        fputc(0x80 | (cp & 0x3F), out);
    }
}

static void writeString(FILE* out, const char* s) {
    fputs(s, out);
}

static void writeUnicodeString(FILE* out, const uint16_t* str, int len) {
    for (int i = 0; i < len; i++) {
        writeUtf8(out, str[i]);
    }
}

static int detectUtf16(const unsigned char* data, uint32_t len) {
    if (len < 2) return 0;
    if (len % 2 != 0) return 0;
    int hasHigh = 0;
    int allLow = 1;
    for (uint32_t i = 0; i + 1 < len; i += 2) {
        if (data[i + 1] != 0) {
            hasHigh = 1;
            break;
        }
        if (data[i] == 0) break;
    }
    for (uint32_t i = 1; i < len; i += 2) {
        if (data[i] != 0) { allLow = 0; break; }
    }
    if (allLow) return 0;
    return hasHigh;
}

static void writeBodyUtf16(FILE* out, const unsigned char* buf, uint32_t len) {
    int inTag = 0;
    for (uint32_t i = 0; i + 1 < len; i += 2) {
        uint16_t wc;
        memcpy(&wc, buf + i, 2);
        if (wc == 0) break;

        if (wc == 0x0A) {
            writeString(out, "\n\t[m1]");
        } else if (wc == 0x09) {
            writeString(out, "\t[m2]");
        } else if (wc < 0x20) {
            fputc(' ', out);
        } else if (wc == 0x5C && i + 2 < len) {
            uint16_t esc;
            memcpy(&esc, buf + i + 2, 2);
            i += 2;
            switch (esc) {
                case 0x22: writeString(out, "[i][ref]\"[/ref][/i]"); break;
                case 0x2A: fputc('*', out); break;
                case 0x2C: fputc(',', out); break;
                case 0x2E: fputc('.', out); break;
                case 0x21: fputc('!', out); break;
                case 0x3F: fputc('?', out); break;
                default: writeUtf8(out, esc); break;
            }
        } else if (wc < 0x80) {
            if ((unsigned char)wc == '{') {
                inTag = 1;
            } else if (inTag) {
                if ((unsigned char)wc == '}') inTag = 0;
            } else {
                fputc((int)wc, out);
            }
        } else {
            if (wc >= 0x2010 && wc <= 0x2015) fputc('-', out);
            else if (wc >= 0x2018 && wc <= 0x201B) fputc('\'', out);
            else if (wc >= 0x201C && wc <= 0x201F) fputc('"', out);
            else if (wc >= 0x2020 && wc <= 0x2027) fputc('*', out);
            else if (wc >= 0x2030 && wc <= 0x2033) fputc('x', out);
            else if (wc == 0x00AB || wc == 0x00BB) fputc('"', out);
            else if (wc == 0x00AD) fputc('-', out);
            else if (wc == 0x00A0) fputc(' ', out);
            else writeUtf8(out, wc);
        }
    }
}

static void writeBodySingle(FILE* out, const unsigned char* buf, uint32_t len) {
    int inTag = 0;
    for (uint32_t i = 0; i < len; i++) {
        unsigned char c = buf[i];
        if (c == 0) break;

        if (c == '\n') {
            writeString(out, "\n\t[m1]");
        } else if (c == '\t') {
            writeString(out, "\t[m2]");
        } else if (c < 0x20) {
            fputc(' ', out);
        } else if (c == '\\' && i + 1 < len) {
            i++;
            unsigned char esc = buf[i];
            switch (esc) {
                case '"': writeString(out, "[i][ref]\"[/ref][/i]"); break;
                case '*': fputc('*', out); break;
                case ',': fputc(',', out); break;
                case '.': fputc('.', out); break;
                case '!': fputc('!', out); break;
                case '?': fputc('?', out); break;
                default: fputc((int)esc, out); break;
            }
        } else if ((c & 0x80) == 0) {
            if (c == '{') { inTag = 1; }
            else if (inTag) { if (c == '}') inTag = 0; }
            else { fputc((int)c, out); }
        } else {
            if (i + 1 < len) {
                uint16_t wc;
                memcpy(&wc, buf + i, 2);
                i++;
                if (wc >= 0x2010 && wc <= 0x2015) fputc('-', out);
                else if (wc >= 0x2018 && wc <= 0x201B) fputc('\'', out);
                else if (wc >= 0x201C && wc <= 0x201F) fputc('"', out);
                else if (wc >= 0x2020 && wc <= 0x2027) fputc('*', out);
                else if (wc >= 0x2030 && wc <= 0x2033) fputc('x', out);
                else if (wc == 0x00AB || wc == 0x00BB) fputc('"', out);
                else if (wc == 0x00AD) fputc('-', out);
                else if (wc == 0x00A0) fputc(' ', out);
                else writeUtf8(out, wc);
            }
        }
    }
}

EXPORT int decode_lsd(const char* inputPath, const char* outputPath) {
    if (!inputPath || !outputPath) {
        setError("Null path provided");
        return -1;
    }

    FILE* in = fopen(inputPath, "rb");
    if (!in) {
        setError("Cannot open input .lsd file");
        return -1;
    }

    FILE* out = fopen(outputPath, "wb");
    if (!out) {
        fclose(in);
        setError("Cannot create output .dsl file");
        return -1;
    }

    unsigned char header[8];
    if (fread(header, 1, 8, in) != 8) {
        fclose(in); fclose(out);
        setError("Failed to read header");
        return -1;
    }

    if (header[0] != 0x4C || header[1] != 0x69 ||
        header[2] != 0x6E || header[3] != 0x67 ||
        header[4] != 0x56 || header[5] != 0x6F) {
        char err[256];
        snprintf(err, sizeof(err),
            "Not a valid LSD file: expected 'LingVo', got bytes: "
            "%02X %02X %02X %02X %02X %02X %02X %02X",
            header[0], header[1], header[2], header[3],
            header[4], header[5], header[6], header[7]);
        fclose(in); fclose(out);
        setError(err);
        return -1;
    }

    fseek(in, 0, SEEK_END);
    long fileSize = ftell(in);
    fseek(in, 0, SEEK_SET);

    writeString(out, "#NAME\t\"Dictionary\"\n");
    writeString(out, "#INDEX_LANGUAGE\t\"English\"\n");
    writeString(out, "#CONTENTS_LANGUAGE\t\"English\"\n\n");

    unsigned char* buf = (unsigned char*)malloc(65536);
    if (!buf) {
        fclose(in); fclose(out);
        setError("Memory allocation failed");
        return -1;
    }

    long pos = 8;
    int entryCount = 0;
    int globalUtf16 = -1;

    while (pos < fileSize) {
        fseek(in, pos, SEEK_SET);

        uint32_t entryLen;
        if (fread(buf, 1, 4, in) != 4) break;
        memcpy(&entryLen, buf, 4);

        if (entryLen == 0 || entryLen > 100000) break;

        uint32_t wordLen;
        if (fread(buf, 1, 4, in) != 4) break;
        memcpy(&wordLen, buf, 4);

        if (wordLen > entryLen || wordLen == 0) break;

        uint32_t bodyLen = entryLen - 4 - wordLen;

        if (fread(buf, 1, wordLen, in) != wordLen) break;

        if (globalUtf16 < 0) {
            globalUtf16 = detectUtf16(buf, wordLen);
        }

        uint16_t wordBuf[4096];
        int wordChars = 0;

        if (globalUtf16) {
            for (uint32_t k = 0; k + 1 < wordLen && wordChars < 4095; k += 2) {
                uint16_t cu;
                memcpy(&cu, buf + k, 2);
                wordBuf[wordChars++] = cu;
            }
        } else {
            for (uint32_t k = 0; k < wordLen && wordChars < 4095; k++) {
                wordBuf[wordChars++] = buf[k];
            }
        }

        writeUnicodeString(out, wordBuf, wordChars);
        fputc('\n', out);

        if (bodyLen > 0 && bodyLen <= 60000) {
            if (fread(buf, 1, bodyLen, in) != bodyLen) break;

            writeString(out, "\t[m1]");
            if (globalUtf16) {
                writeBodyUtf16(out, buf, bodyLen);
            } else {
                writeBodySingle(out, buf, bodyLen);
            }
        }

        writeString(out, "\n\n");
        entryCount++;
        pos += entryLen;
    }

    free(buf);
    fclose(in);
    fclose(out);

    return entryCount;
}

EXPORT int get_last_error(char* buffer, int bufferSize) {
    if (buffer && bufferSize > 0) {
        strncpy(buffer, lastError, bufferSize - 1);
        buffer[bufferSize - 1] = '\0';
    }
    return (int)strlen(lastError);
}
