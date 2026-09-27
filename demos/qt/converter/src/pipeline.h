#pragma once
#include <QImage>
#include <QRect>
#include <QTemporaryDir>
#include <QVariantMap>
#include <atomic>
#include <functional>
#include <memory>
#include <vector>

namespace pc {
constexpr qint64 MiB = 1024 * 1024;
struct Error {
    QString message;
};
struct Tools {
    QString ffmpeg, ffprobe;
    static Tools locate();
};
struct Media {
    QString path, codec, format;
    int width = 0, height = 0;
    double duration = 0, fps = 0, startTime = 0;
    bool alpha = false;
    QVariantMap map() const;
};
struct Options {
    double start = 0, end = 0, fps = 0;
    QRect crop;
    int width = 128, height = 128, colors = 0, mergeTolerance = 0, keyTolerance = 24;
    bool nearest = true, merge = true, dither = false, key = false;
    QRgb keyColor = qRgb(0, 255, 0);
    quint32 plays = 0;
    static Options defaults(const Media &);
    static Options fromMap(const QVariantMap &, const Media &);
    QVariantMap map() const;
    void validate(const Media &) const;
};
struct Frame {
    qint64 offset = 0, originalOffset = 0, durationUs = 0;
};
struct Clip {
    std::shared_ptr<QTemporaryDir> directory;
    QString rawPath, originalPath, papngPath;
    std::vector<Frame> frames;
    int width = 0, height = 0, decodedFrames = 0, sampledFrames = 0;
    double duration = 0;
    qint64 fileBytes = 0;
    QVariantMap map() const;
};
using Cancel = std::shared_ptr<std::atomic_bool>;
using Progress = std::function<void(QString, double)>;
Media probe(const Tools &, const QString &, const Cancel &);
QImage thumbnail(const Tools &, const Media &, double, const Cancel &);
double adjacentTime(const Tools &, const Media &, double, int, const Cancel &);
Clip convert(const Tools &, const Media &, const Options &, const Cancel &, const Progress &);
QImage frameImage(const Clip &, int, bool original = false);
void save(const Clip &, const QString &target, const Cancel &);
void writePapng(const Clip &, const Media &, const Options &, const Cancel &, const Progress &);
} // namespace pc
