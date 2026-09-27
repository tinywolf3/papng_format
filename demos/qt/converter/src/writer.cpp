#include "pipeline.h"
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtEndian>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <numeric>

namespace pc {
namespace {
void u32(QByteArray &b, quint32 v) {
    char bytes[4];
    qToBigEndian(v, bytes);
    b.append(bytes, 4);
}
void u16(QByteArray &b, quint16 v) {
    char bytes[2];
    qToBigEndian(v, bytes);
    b.append(bytes, 2);
}
quint32 pngCrc(const char *type, const QByteArray &data) {
    static const auto table = [] {
        std::array<quint32, 256> values{};
        for (quint32 n = 0; n < 256; n++) {
            quint32 c = n;
            for (int bit = 0; bit < 8; bit++)
                c = (c >> 1) ^ ((c & 1) ? 0xedb88320U : 0U);
            values[n] = c;
        }
        return values;
    }();
    quint32 crc = 0xffffffffU;
    for (int i = 0; i < 4; i++)
        crc = table[(crc ^ quint8(type[i])) & 255] ^ (crc >> 8);
    for (char byte : data)
        crc = table[(crc ^ quint8(byte)) & 255] ^ (crc >> 8);
    return crc ^ 0xffffffffU;
}
void chunk(QFile &f, const char *type, const QByteArray &data) {
    QByteArray head;
    u32(head, quint32(data.size()));
    head.append(type, 4);
    auto crc = pngCrc(type, data);
    QByteArray tail;
    u32(tail, quint32(crc));
    if (f.write(head) != head.size() || f.write(data) != data.size() || f.write(tail) != tail.size())
        throw Error{"PAPNG 파일 저장 실패"};
}
int paeth(int a, int b, int c) {
    int p = a + b - c, da = std::abs(p - a), db = std::abs(p - b), dc = std::abs(p - c);
    return da <= db && da <= dc ? a : db <= dc ? b : c;
}
// Same six lossless scanline candidates as the editor: five fixed filters and
// one adaptive candidate. Only two uncompressed candidates are retained.
QByteArray compressFrame(const QByteArray &rgba, int width, int height, const Cancel &cancel) {
    int stride = width * 4, rowSize = stride + 1;
    QByteArray rows(rowSize * height, Qt::Uninitialized), adaptive(rows.size(), Qt::Uninitialized), best;
    std::vector<quint64> scores(height, std::numeric_limits<quint64>::max());
    const auto *pixels = reinterpret_cast<const uchar *>(rgba.constData());
    for (int filter = 0; filter < 6; filter++) {
        if (cancel->load())
            throw Error{"작업을 취소했습니다."};
        if (filter < 5)
            for (int y = 0; y < height; y++) {
                char *row = rows.data() + y * rowSize;
                row[0] = char(filter);
                quint64 score = 0;
                for (int x = 0; x < stride; x++) {
                    int here = y * stride + x, a = x >= 4 ? pixels[here - 4] : 0,
                        b = y ? pixels[here - stride] : 0, c = y && x >= 4 ? pixels[here - stride - 4] : 0;
                    int prediction = filter == 0   ? 0
                                     : filter == 1 ? a
                                     : filter == 2 ? b
                                     : filter == 3 ? (a + b) / 2
                                                   : paeth(a, b, c);
                    uchar value = uchar(pixels[here] - prediction);
                    row[x + 1] = char(value);
                    score += std::min(int(value), 256 - int(value));
                }
                if (score < scores[y]) {
                    scores[y] = score;
                    std::memcpy(adaptive.data() + y * rowSize, row, rowSize);
                }
            }
        // qCompress has a four-byte Qt size prefix before the zlib stream.
        auto zipped = qCompress(filter == 5 ? adaptive : rows, 9).mid(4);
        if (zipped.isEmpty())
            throw Error{"PNG 압축 실패"};
        if (best.isEmpty() || zipped.size() < best.size())
            best = std::move(zipped);
    }
    return best;
}
} // namespace
void writePapng(const Clip &clip, const Media &media, const Options &options, const Cancel &cancel,
                const Progress &progress) {
    QFile out(clip.papngPath), raw(clip.rawPath);
    if (!out.open(QIODevice::WriteOnly) || !raw.open(QIODevice::ReadOnly))
        throw Error{"PAPNG 임시 파일을 열 수 없습니다."};
    if (out.write(QByteArray::fromHex("89504e470d0a1a0a")) != 8)
        throw Error{"PAPNG 파일 저장 실패"};
    QByteArray ihdr;
    u32(ihdr, clip.width);
    u32(ihdr, clip.height);
    ihdr.append(QByteArray::fromHex("0806000000"));
    chunk(out, "IHDR", ihdr);
    QByteArray actl;
    u32(actl, quint32(clip.frames.size()));
    u32(actl, options.plays);
    chunk(out, "acTL", actl);
    QByteArray extension("PAPNG\0\0\0", 8);
    u16(extension, 1);
    u16(extension, 1);
    u32(extension, 56);
    extension.append(QByteArray(47, 0));
    chunk(out, "paEX", extension);
    QJsonObject provenance{{"application", "PAPNG Converter"},
                           {"source", QFileInfo(media.path).fileName()},
                           {"settings", QJsonObject::fromVariantMap(options.map())}};
    auto json = QJsonDocument(QJsonObject{{"schema_version", 1}, {"converter", provenance}})
                    .toJson(QJsonDocument::Compact);
    QByteArray metadata("PAPNG.Metadata\0", 15);
    metadata.append(QByteArray::fromHex("01000000"));
    metadata.append(qCompress(json, 9).mid(4));
    chunk(out, "iTXt", metadata);
    quint32 sequence = 0;
    qint64 targetUs = 0;
    long double writtenSeconds = 0;
    for (size_t index = 0; index < clip.frames.size(); index++) {
        if (cancel->load())
            throw Error{"작업을 취소했습니다."};
        const auto &frame = clip.frames[index];
        targetUs += frame.durationUs;
        // Feed rounding error back into the next duration; APNG uses two uint16s.
        long double duration = std::max(1.0L / 65535, targetUs / 1000000.0L - writtenSeconds);
        auto den = quint32(std::clamp(std::floor(65535.0L / duration), 1.0L, 60000.0L));
        auto numerator = quint32(std::clamp(std::round(duration * den), 1.0L, 65535.0L));
        auto divisor = std::gcd(numerator, den);
        numerator /= divisor;
        den /= divisor;
        writtenSeconds += static_cast<long double>(numerator) / den;
        QByteArray control;
        u32(control, sequence++);
        u32(control, clip.width);
        u32(control, clip.height);
        u32(control, 0);
        u32(control, 0);
        u16(control, numerator);
        u16(control, den);
        control.append(char(0));
        control.append(char(0));
        chunk(out, "fcTL", control);
        if (!raw.seek(frame.offset))
            throw Error{"프레임 읽기 실패"};
        auto bytes = raw.read(qint64(clip.width) * clip.height * 4);
        if (bytes.size() != qint64(clip.width) * clip.height * 4)
            throw Error{"불완전한 프레임"};
        auto compressed = compressFrame(bytes, clip.width, clip.height, cancel);
        if (index == 0)
            chunk(out, "IDAT", compressed);
        else {
            QByteArray data;
            u32(data, sequence++);
            data += compressed;
            chunk(out, "fdAT", data);
        }
        progress("PAPNG 무손실 압축", 0.78 + 0.22 * double(index + 1) / clip.frames.size());
    }
    chunk(out, "IEND", {});
    if (!out.flush())
        throw Error{"PAPNG 파일 저장 실패"};
}
} // namespace pc
