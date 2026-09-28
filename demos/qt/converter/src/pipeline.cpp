#include "pipeline.h"
#include <QColor>
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>
#include <array>
#include <climits>
#include <cmath>
#include <numeric>

namespace pc {
namespace {
void require(bool valid, QString message) {
    if (!valid)
        throw Error{message};
}
void checkCancel(const Cancel &c) {
    if (c->load())
        throw Error{QStringLiteral("작업을 취소했습니다.")};
}
QString num(double v) { return QString::number(v, 'f', 9); }
QString program(QString name) {
#ifdef Q_OS_WIN
    name += ".exe";
#endif
    auto bundled = QCoreApplication::applicationDirPath() + "/tools/" + name;
    if (QFileInfo(bundled).isExecutable())
        return bundled;
    auto supplied = qEnvironmentVariable("PAPNG_FFMPEG_DIR");
    if (!supplied.isEmpty() && QFileInfo(supplied + "/" + name).isExecutable())
        return QDir(supplied).absoluteFilePath(name);
    return QStandardPaths::findExecutable(name); // Development runs; packages bundle both tools.
}
// Each tool is invoked directly with an argument array, never through a shell.
QByteArray run(const QString &executable, const QStringList &args, const Cancel &cancel, int timeout,
               std::function<void(QByteArray)> output = {}, std::function<void(QByteArray)> log = {}) {
    require(!executable.isEmpty(), "FFmpeg 도구가 없습니다. 전체 배포본을 사용하세요.");
    QProcess p;
    p.setProcessChannelMode(QProcess::SeparateChannels);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert("AV_LOG_FORCE_NOCOLOR", "1");
#ifndef Q_OS_WIN
    const auto lib = QCoreApplication::applicationDirPath() + "/lib";
    if (QDir(lib).exists())
        env.insert("LD_LIBRARY_PATH", lib + ":" + env.value("LD_LIBRARY_PATH"));
#endif
    p.setProcessEnvironment(env);
    p.start(executable, args, QIODevice::ReadOnly);
    require(p.waitForStarted(5000), "영상 도구를 실행하지 못했습니다: " + p.errorString());
    QElapsedTimer timer;
    timer.start();
    QByteArray result, errors;
    auto drain = [&] {
        auto bytes = p.readAllStandardOutput();
        if (output)
            output(bytes);
        else {
            result += bytes;
            require(result.size() <= 16 * MiB, "영상 정보가 처리 예산을 초과했습니다.");
        }
        auto text = p.readAllStandardError();
        if (log)
            log(text);
        errors += text;
        if (errors.size() > 16384)
            errors = errors.right(16384);
    };
    try {
        while (p.state() != QProcess::NotRunning) {
            checkCancel(cancel);
            require(timer.elapsed() < timeout,
                    "영상 처리가 제한 시간을 초과했습니다. 구간이나 크기를 줄여 주세요.");
            p.waitForReadyRead(25);
            drain();
        }
        drain();
        checkCancel(cancel);
        require(p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0,
                "영상 도구 처리 실패:\n" + QString::fromUtf8(errors.right(2400)));
    } catch (...) {
        p.kill();
        p.waitForFinished(3000);
        throw;
    }
    return result;
}
QStringList gifOptions(const Media &m) {
    // Keep zero-delay duration estimates consistent with GIF packet timestamps (100 ms).
    // Explicit nonzero delays, including 10 ms, remain unchanged.
    return m.format.contains("gif")
               ? QStringList{"-ignore_loop", "1", "-min_delay", "1", "-default_delay", "10"}
               : QStringList{};
}
QStringList decoderOptions(const Media &m) {
    if (m.alpha && m.codec == "vp9")
        return {"-c:v", "libvpx-vp9"};
    if (m.alpha && m.codec == "vp8")
        return {"-c:v", "libvpx"};
    return {};
}
QStringList frameProbeArgs(const Media &m, double time, double radius) {
    return QStringList{"-v", "error", "-protocol_whitelist", "file,pipe"} + gifOptions(m) +
           QStringList{"-read_intervals",
                       num(std::max(0.0, time - radius) + m.startTime) + "%" +
                           num(std::min(m.duration, time + radius) + m.startTime),
                       "-select_streams",
                       "v:0",
                       "-show_entries",
                       "frame=best_effort_timestamp_time",
                       "-of",
                       "csv=p=0",
                       m.path};
}
std::vector<double> nearby(const Tools &t, const Media &m, double time, const Cancel &c, double radius = 2) {
    const auto text = run(t.ffprobe, frameProbeArgs(m, time, radius), c, 15000);
    std::vector<double> times;
    for (const auto &line : text.split('\n')) {
        bool ok;
        auto value = line.split(',').value(0).toDouble(&ok);
        if (ok && std::isfinite(value))
            times.push_back(value - m.startTime);
    }
    std::sort(times.begin(), times.end());
    return times;
}
QByteArray readFrame(QFile &file, qint64 offset, qint64 size) {
    require(file.seek(offset), "미리보기 프레임 위치 오류");
    auto bytes = file.read(size);
    require(bytes.size() == size, "임시 프레임을 읽지 못했습니다.");
    return bytes;
}
void keyImage(QByteArray &b, const Options &o) {
    if (!o.key)
        return;
    auto *p = reinterpret_cast<uchar *>(b.data());
    for (qsizetype i = 0; i < b.size(); i += 4) {
        int dr = int(p[i]) - qRed(o.keyColor), dg = int(p[i + 1]) - qGreen(o.keyColor),
            db = int(p[i + 2]) - qBlue(o.keyColor);
        if (dr * dr + dg * dg + db * db <= 3 * o.keyTolerance * o.keyTolerance)
            p[i + 3] = 0;
    }
}
struct Bin {
    quint64 r = 0, g = 0, b = 0, w = 0;
};
int binAt(const uchar *p) { return (int(p[0] >> 3) << 10) | (int(p[1] >> 3) << 5) | (p[2] >> 3); }
struct Color {
    int r, g, b;
    quint64 w;
};
// A bounded, alpha-weighted histogram produces one shared palette for the entire clip.
std::vector<QRgb> palette(const std::vector<Bin> &bins, int count) {
    std::vector<Color> colors;
    for (auto &b : bins)
        if (b.w)
            colors.push_back(
                {int((b.r + b.w / 2) / b.w), int((b.g + b.w / 2) / b.w), int((b.b + b.w / 2) / b.w), b.w});
    if (colors.empty())
        return {qRgb(0, 0, 0)};
    std::vector<std::vector<int>> boxes(1);
    boxes[0].resize(colors.size());
    std::iota(boxes[0].begin(), boxes[0].end(), 0);
    auto span = [&](const std::vector<int> &box) {
        std::array<int, 3> lo{255, 255, 255}, hi{0, 0, 0};
        quint64 weight = 0;
        for (int i : box) {
            auto c = colors[i];
            int v[] = {c.r, c.g, c.b};
            for (int k = 0; k < 3; k++) {
                lo[k] = std::min(lo[k], v[k]);
                hi[k] = std::max(hi[k], v[k]);
            }
            weight += c.w;
        }
        int channel = 0;
        for (int k = 1; k < 3; k++)
            if (hi[k] - lo[k] > hi[channel] - lo[channel])
                channel = k;
        return std::pair<int, double>{channel, double(weight) * (hi[channel] - lo[channel])};
    };
    while (int(boxes.size()) < count) {
        int chosen = -1;
        double best = -1;
        for (int i = 0; i < int(boxes.size()); i++)
            if (boxes[i].size() > 1 && span(boxes[i]).second > best) {
                chosen = i;
                best = span(boxes[i]).second;
            }
        if (chosen < 0)
            break;
        auto box = std::move(boxes[chosen]);
        int channel = span(box).first;
        auto component = [&](int i) {
            auto c = colors[i];
            return channel == 0 ? c.r : channel == 1 ? c.g : c.b;
        };
        std::stable_sort(box.begin(), box.end(), [&](int a, int b) { return component(a) < component(b); });
        quint64 total = 0, current = 0;
        for (int i : box)
            total += colors[i].w;
        size_t split = 1;
        for (; split < box.size(); split++) {
            current += colors[box[split - 1]].w;
            if (current >= total / 2)
                break;
        }
        split = std::min(split, box.size() - 1);
        boxes[chosen] = {box.begin(), box.begin() + split};
        boxes.emplace_back(box.begin() + split, box.end());
    }
    std::vector<QRgb> result;
    for (auto &box : boxes) {
        Bin b;
        for (int i : box) {
            auto c = colors[i];
            b.r += c.r * c.w;
            b.g += c.g * c.w;
            b.b += c.b * c.w;
            b.w += c.w;
        }
        result.push_back(qRgb((b.r + b.w / 2) / b.w, (b.g + b.w / 2) / b.w, (b.b + b.w / 2) / b.w));
    }
    return result;
}
QRgb closest(int r, int g, int b, const std::vector<QRgb> &pal) {
    QRgb best = pal[0];
    int distance = INT_MAX;
    for (auto color : pal) {
        int dr = r - qRed(color), dg = g - qGreen(color), db = b - qBlue(color),
            d = dr * dr + dg * dg + db * db;
        if (d < distance) {
            distance = d;
            best = color;
        }
    }
    return best;
}
bool same(const QByteArray &a, const QByteArray &b, int tolerance) {
    if (tolerance == 0)
        return a == b;
    for (qsizetype i = 0; i < a.size(); i++)
        if (std::abs(int(uchar(a[i])) - int(uchar(b[i]))) > tolerance)
            return false;
    return true;
}
} // namespace
Tools Tools::locate() { return {program("ffmpeg"), program("ffprobe")}; }
QVariantMap Media::map() const {
    return {{"path", path},     {"name", QFileInfo(path).fileName()},
            {"codec", codec},   {"width", width},
            {"height", height}, {"duration", duration},
            {"fps", fps},       {"alpha", alpha}};
}
QVariantMap Clip::map() const {
    return {{"width", width},
            {"height", height},
            {"frames", int(frames.size())},
            {"decoded", decodedFrames},
            {"sampled", sampledFrames},
            {"duration", duration},
            {"bytes", fileBytes},
            {"memory", qint64(width) * height * 4 * qint64(frames.size())}};
}
Options Options::defaults(const Media &m) {
    Options o;
    o.end = std::min(m.format.contains("gif") ? 60.0 : 3.0, m.duration);
    o.crop = {0, 0, m.width, m.height};
    o.width = std::min(128, m.width);
    o.height = std::max(1, qRound(double(o.width) * m.height / m.width));
    if (o.height > 128) {
        o.height = 128;
        o.width = std::max(1, qRound(double(o.height) * m.width / m.height));
    }
    return o;
}
QVariantMap Options::map() const {
    return {{"start", start},
            {"end", end},
            {"fps", fps},
            {"x", crop.x()},
            {"y", crop.y()},
            {"cropWidth", crop.width()},
            {"cropHeight", crop.height()},
            {"width", width},
            {"height", height},
            {"colors", colors},
            {"nearest", nearest},
            {"merge", merge},
            {"mergeTolerance", mergeTolerance},
            {"dither", dither},
            {"key", key},
            {"keyColor", QColor(keyColor).name()},
            {"keyTolerance", keyTolerance},
            {"plays", plays}};
}
Options Options::fromMap(const QVariantMap &map, const Media &m) {
    auto v = defaults(m).map();
    for (auto i = map.begin(); i != map.end(); ++i)
        v[i.key()] = i.value();
    Options o;
    o.start = v["start"].toDouble();
    o.end = v["end"].toDouble();
    o.fps = v["fps"].toDouble();
    o.crop = {v["x"].toInt(), v["y"].toInt(), v["cropWidth"].toInt(), v["cropHeight"].toInt()};
    o.width = v["width"].toInt();
    o.height = v["height"].toInt();
    o.colors = v["colors"].toInt();
    o.nearest = v["nearest"].toBool();
    o.merge = v["merge"].toBool();
    o.mergeTolerance = v["mergeTolerance"].toInt();
    o.dither = v["dither"].toBool();
    o.key = v["key"].toBool();
    o.keyColor = QColor(v["keyColor"].toString()).rgba();
    o.keyTolerance = v["keyTolerance"].toInt();
    o.plays = v["plays"].toUInt();
    return o;
}
void Options::validate(const Media &m) const {
    require(std::isfinite(start) && std::isfinite(end) && start >= 0 && end > start &&
                end <= m.duration + 0.001 && end - start <= 60,
            "사용 구간은 원본 안에서 0초 초과·60초 이하여야 합니다.");
    require(width >= 1 && height >= 1 && width <= 512 && height <= 512,
            "출력 크기는 가로·세로 1~512픽셀입니다.");
    require(crop.width() > 0 && crop.height() > 0 && crop.x() >= 0 && crop.y() >= 0 &&
                qint64(crop.x()) + crop.width() <= m.width && qint64(crop.y()) + crop.height() <= m.height,
            "자르기 영역이 원본을 벗어납니다.");
    require(std::isfinite(fps) && (fps == 0 || (fps >= 1 && fps <= 60)), "FPS는 원본 유지 또는 1~60입니다.");
    require(colors == 0 || (colors >= 2 && colors <= 256), "색상 수는 유지 또는 2~256입니다.");
    require(mergeTolerance >= 0 && mergeTolerance <= 16 && keyTolerance >= 0 && keyTolerance <= 255,
            "색상 허용 오차가 범위를 벗어납니다.");
}
Media probe(const Tools &t, const QString &input, const Cancel &cancel) {
    QFileInfo file(input);
    require(file.isFile(), "영상 파일을 선택하세요.");
    auto ext = file.suffix().toLower();
    require(QStringList{"mp4", "webm", "gif"}.contains(ext), "MP4·WebM·GIF 파일을 선택하세요.");
    Media m;
    m.path = file.absoluteFilePath();
    m.format = ext;
    auto bytes = run(
        t.ffprobe,
        QStringList{"-v", "error", "-protocol_whitelist", "file,pipe"} + gifOptions(m) +
            QStringList{"-select_streams", "v:0", "-show_entries",
                        "stream=codec_name,width,height,avg_frame_rate,r_frame_rate,duration,start_time,pix_"
                        "fmt:stream_tags=alpha_mode:stream_side_data=rotation:format=duration,format_name",
                        "-of", "json", m.path},
        cancel, 15000);
    // ffprobe's output is an external strict-JSON contract.
    QJsonParseError error;
    auto doc = QJsonDocument::fromJson(bytes, &error);
    require(error.error == QJsonParseError::NoError, "영상 정보를 읽지 못했습니다.");
    auto root = doc.object();
    auto streams = root["streams"].toArray();
    require(!streams.isEmpty(), "영상 스트림이 없습니다.");
    auto s = streams[0].toObject();
    m.width = s["width"].toInt();
    m.height = s["height"].toInt();
    m.codec = s["codec_name"].toString();
    m.format = root["format"].toObject()["format_name"].toString();
    require(m.format.contains("gif") || m.format.contains("mov") || m.format.contains("matroska") ||
                m.format.contains("webm"),
            "지원하는 영상 컨테이너가 아닙니다.");
    m.startTime = s["start_time"].toString().toDouble();
    m.duration = s["duration"].toString().toDouble();
    if (m.duration <= 0)
        m.duration = root["format"].toObject()["duration"].toString().toDouble();
    if (m.format.contains("gif")) {
        // GIF header duration estimates can omit frames without a control extension.
        // Use the same packet timeline as decoding, including zero-delay fallback.
        const auto packets = run(t.ffprobe,
            QStringList{"-v", "error", "-protocol_whitelist", "file,pipe"} + gifOptions(m) +
            QStringList{"-select_streams", "v:0", "-show_entries", "packet=pts_time,duration_time",
                        "-of", "csv=p=0", m.path}, cancel, 15000);
        double end = m.startTime;
        for (const auto &line : packets.split('\n')) {
            const auto fields = line.split(',');
            if (fields.size() != 2) continue;
            bool validTime = false, validDelay = false;
            const double time = fields[0].toDouble(&validTime);
            const double delay = fields[1].toDouble(&validDelay);
            require(validTime && validDelay && std::isfinite(time) && std::isfinite(delay) && delay > 0,
                    "GIF 프레임 시간을 읽지 못했습니다.");
            end = std::max(end, time + delay);
        }
        m.duration = end - m.startTime;
    }
    auto fps = s["avg_frame_rate"].toString().split('/');
    if (fps.size() == 2 && fps[1].toDouble() > 0)
        m.fps = fps[0].toDouble() / fps[1].toDouble();
    if (m.fps <= 0) {
        fps = s["r_frame_rate"].toString().split('/');
        if (fps.size() == 2 && fps[1].toDouble() > 0)
            m.fps = fps[0].toDouble() / fps[1].toDouble();
    }
    for (auto side : s["side_data_list"].toArray())
        if (std::abs(qRound(side.toObject()["rotation"].toDouble())) % 180 == 90)
            std::swap(m.width, m.height);
    auto pix = s["pix_fmt"].toString();
    m.alpha = pix.contains("rgba") || pix.contains("bgra") || pix.contains("yuva") || pix.contains("gbrap") ||
              m.format.contains("gif") || s["tags"].toObject()["alpha_mode"].toString() == "1";
    require(m.width > 0 && m.height > 0 && qint64(m.width) * m.height <= 3840LL * 2160,
            "원본은 4K에 해당하는 829만 픽셀 이하를 지원합니다.");
    require(std::isfinite(m.duration) && m.duration > 0, "재생 시간을 확인할 수 없는 영상입니다.");
    return m;
}
QImage thumbnail(const Tools &t, const Media &m, double time, const Cancel &c, bool fullResolution) {
    double anchor = 0;
    for (double stamp : nearby(t, m, time, c))
        if (stamp <= time + 0.000001)
            anchor = std::max(anchor, stamp);
    auto args = QStringList{"-hide_banner", "-loglevel",       "error", "-nostdin", "-protocol_whitelist",
                            "file,pipe",    "-filter_threads", "1",     "-threads", "2"} +
                gifOptions(m) + decoderOptions(m) +
                QStringList{"-ss",
                            num(std::max(0.0, anchor - 0.000001)),
                            "-i",
                            m.path,
                            "-map",
                            "0:v:0",
                            "-an",
                            "-sn",
                            "-frames:v",
                            "1",
                            "-vf",
                            fullResolution ? "setsar=1" :
                            "scale='min(1024,iw)':'min(1024,ih)':force_original_aspect_ratio=decrease:flags=neighbor,setsar=1",
                            "-threads",
                            "1",
                            "-f",
                            "image2pipe",
                            "-c:v",
                            "png",
                            "-pix_fmt",
                            "rgba",
                            "pipe:1"};
    QByteArray bytes;
    run(t.ffmpeg, args, c, 15000, [&](QByteArray part) {
        require(bytes.size() + part.size() <= 64 * MiB, "원본 프레임이 미리보기 한도를 초과했습니다.");
        bytes += part;
    });
    QImage image;
    require(image.loadFromData(bytes, "PNG"), "미리보기 프레임을 읽지 못했습니다.");
    return image;
}
double adjacentTime(const Tools &t, const Media &m, double time, int direction, const Cancel &c) {
    // Expand the lookup for GIFs with long held frames; do not assume an FPS grid.
    for (double radius = 2;; radius = std::min(m.duration + 1, radius * 4)) {
        auto times = nearby(t, m, time, c, radius);
        if (direction > 0) {
            for (double v : times)
                if (v > time + 0.00001)
                    return std::min(v, m.duration - 0.000001);
        } else {
            for (auto i = times.rbegin(); i != times.rend(); ++i)
                if (*i < time - 0.00001)
                    return std::max(0.0, *i);
        }
        if (radius >= m.duration || (direction < 0 && time - radius <= 0) ||
            (direction > 0 && time + radius >= m.duration))
            return time;
    }
}
Clip convert(const Tools &t, const Media &m, const Options &o, const Cancel &cancel,
             const Progress &progress) {
    o.validate(m);
    checkCancel(cancel);
    progress("프레임 시간 확인", 0);
    double anchor = 0;
    if (o.start > 0) {
        auto times = nearby(t, m, o.start, cancel);
        for (double time : times)
            if (time <= o.start + 0.000001)
                anchor = std::max(anchor, time);
    }
    Clip clip;
    clip.directory = std::make_shared<QTemporaryDir>(QDir::tempPath() + "/papng-converter-XXXXXX");
    require(clip.directory->isValid(), "임시 작업 공간을 만들 수 없습니다.");
    clip.width = o.width;
    clip.height = o.height;
    clip.duration = o.end - o.start;
    clip.originalPath = clip.directory->filePath("decoded.rgba");
    clip.rawPath = clip.directory->filePath("frames.rgba");
    clip.papngPath = clip.directory->filePath("preview.papng");
    QFile raw(clip.originalPath);
    require(raw.open(QIODevice::WriteOnly), "임시 프레임 파일을 만들 수 없습니다.");
    const qint64 frameBytes = qint64(o.width) * o.height * 4;
    std::vector<double> times;
    QByteArray lines;
    qint64 received = 0;
    QRegularExpression info("\\bn:\\s*(\\d+)\\s+pts:\\s*[-\\d]+\\s+pts_time:([-+\\d.eE]+)");
    auto filter = QString("crop=%1:%2:%3:%4:exact=1,scale=%5:%6:flags=%7,setsar=1,format=rgba,showinfo")
                      .arg(o.crop.width())
                      .arg(o.crop.height())
                      .arg(o.crop.x())
                      .arg(o.crop.y())
                      .arg(o.width)
                      .arg(o.height)
                      .arg(o.nearest ? "neighbor" : "lanczos");
    auto args = QStringList{"-hide_banner", "-loglevel",       "info", "-nostdin", "-protocol_whitelist",
                            "file,pipe",    "-filter_threads", "1",    "-threads", "2"} +
                gifOptions(m) + decoderOptions(m) +
                QStringList{"-ss",         num(std::max(0.0, anchor - 0.000001)),
                            "-t",          num(o.end - anchor + 0.000001),
                            "-i",          m.path,
                            "-map",        "0:v:0",
                            "-an",         "-sn",
                            "-dn",         "-vf",
                            filter,        "-fps_mode",
                            "passthrough", "-threads",
                            "1",           "-f",
                            "rawvideo",    "-pix_fmt",
                            "rgba",        "pipe:1"};
    progress("선택 구간 디코딩", 0.02);
    run(
        t.ffmpeg, args, cancel, 180000,
        [&](QByteArray bytes) {
            received += bytes.size();
            require(received <= 256 * MiB && received / frameBytes <= 10000,
                    "변환 작업 공간을 초과했습니다. 구간이나 출력 크기를 줄여 주세요.");
            require(raw.write(bytes) == bytes.size(), "임시 프레임 저장 실패");
        },
        [&](QByteArray text) {
            lines += text;
            require(lines.size() < MiB, "영상 시간 정보가 잘못되었습니다.");
            int newline;
            while ((newline = lines.indexOf('\n')) >= 0) {
                auto line = QString::fromUtf8(lines.left(newline));
                lines.remove(0, newline + 1);
                auto match = info.match(line);
                if (match.hasMatch()) {
                    int index = match.captured(1).toInt();
                    double time = match.captured(2).toDouble() + anchor;
                    require(index == int(times.size()) && std::isfinite(time) && times.size() < 10001,
                            "프레임 시간 순서 오류");
                    times.push_back(time);
                    progress("선택 구간 디코딩",
                             0.02 + 0.48 * std::clamp((time - o.start) / clip.duration, 0.0, 1.0));
                }
            }
        });
    raw.close();
    require(received > 0 && received % frameBytes == 0, "영상에서 완전한 프레임을 얻지 못했습니다.");
    const int count = int(received / frameBytes);
    require(int(times.size()) >= count, "영상 프레임 시간 정보가 부족합니다.");
    times.resize(count);
    clip.decodedFrames = count;
    for (size_t i = 1; i < times.size(); i++)
        require(times[i] >= times[i - 1], "역순 프레임 시간은 지원하지 않습니다.");
    struct Sample {
        int source;
        qint64 duration;
    };
    std::vector<Sample> samples;
    if (o.fps > 0) {
        size_t index = 0;
        for (int n = 0; double(n) / o.fps < clip.duration - 0.0000001; n++) {
            double time = o.start + double(n) / o.fps;
            while (index + 1 < times.size() && times[index + 1] <= time + 0.000001)
                index++;
            samples.push_back({int(index), qRound64((std::min(o.end, time + 1 / o.fps) - time) * 1e6)});
            require(samples.size() <= 3600, "요청한 프레임 수가 너무 많습니다.");
        }
    } else
        for (int i = 0; i < count; i++) {
            double from = std::max(o.start, times[i]),
                   to = std::min(o.end, i + 1 < count ? times[i + 1] : o.end);
            if (i == 0)
                from = o.start;
            if (to > from)
                samples.push_back({i, qRound64((to - from) * 1e6)});
        }
    require(!samples.empty(), "선택 구간에 프레임이 없습니다.");
    clip.sampledFrames = int(samples.size());
    require(raw.open(QIODevice::ReadOnly), "임시 프레임을 열지 못했습니다.");
    std::vector<QRgb> pal;
    std::vector<QRgb> lookup(32768);
    if (o.colors) {
        std::vector<Bin> bins(32768);
        for (size_t f = 0; f < samples.size(); f++) {
            checkCancel(cancel);
            auto bytes = readFrame(raw, samples[f].source * frameBytes, frameBytes);
            keyImage(bytes, o);
            const auto *p = reinterpret_cast<const uchar *>(bytes.constData());
            quint64 duration = std::max<qint64>(1, samples[f].duration / 1000);
            for (qint64 i = 0; i < frameBytes; i += 4) {
                auto &b = bins[binAt(p + i)];
                quint64 w = p[i + 3] * duration;
                b.r += p[i] * w;
                b.g += p[i + 1] * w;
                b.b += p[i + 2] * w;
                b.w += w;
            }
            progress("구간 공통 팔레트 계산", 0.5 + 0.1 * double(f + 1) / samples.size());
        }
        pal = palette(bins, o.colors);
        for (int n = 0; n < 32768; n++) {
            auto &b = bins[n];
            int r = b.w ? b.r / b.w : ((n >> 10) & 31) * 8 + 4, g = b.w ? b.g / b.w : ((n >> 5) & 31) * 8 + 4,
                blue = b.w ? b.b / b.w : (n & 31) * 8 + 4;
            lookup[n] = closest(r, g, blue, pal);
        }
    }
    QFile output(clip.rawPath);
    require(output.open(QIODevice::WriteOnly), "변환 프레임을 저장하지 못했습니다.");
    QByteArray last;
    constexpr int bayer[] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
    for (size_t n = 0; n < samples.size(); n++) {
        checkCancel(cancel);
        auto sample = samples[n];
        auto bytes = readFrame(raw, sample.source * frameBytes, frameBytes);
        keyImage(bytes, o);
        if (o.colors) {
            auto *p = reinterpret_cast<uchar *>(bytes.data());
            for (qint64 i = 0; i < frameBytes; i += 4) {
                if (!p[i + 3])
                    continue;
                QRgb color;
                if (o.dither) {
                    int pixel = i / 4, delta = (bayer[(pixel / o.width % 4) * 4 + pixel % 4] - 8) * 2;
                    color = closest(std::clamp(int(p[i]) + delta, 0, 255),
                                    std::clamp(int(p[i + 1]) + delta, 0, 255),
                                    std::clamp(int(p[i + 2]) + delta, 0, 255), pal);
                } else
                    color = lookup[binAt(p + i)];
                p[i] = qRed(color);
                p[i + 1] = qGreen(color);
                p[i + 2] = qBlue(color);
            }
        }
        if (o.merge && !last.isEmpty() && same(last, bytes, o.mergeTolerance))
            clip.frames.back().durationUs += sample.duration;
        else {
            require(clip.frames.size() < 600 && (qint64(clip.frames.size()) + 1) * frameBytes <= 64 * MiB,
                    "결과가 600프레임 또는 RGBA 64 MiB를 초과합니다. 구간·출력 크기·FPS를 줄여 주세요.");
            clip.frames.push_back({output.pos(), sample.source * frameBytes, sample.duration, times[sample.source]});
            require(output.write(bytes) == bytes.size(), "변환 프레임 저장 실패");
            last = bytes;
        }
        progress("픽셀화와 중복 프레임 정리", 0.6 + 0.18 * double(n + 1) / samples.size());
    }
    output.close();
    raw.close();
    writePapng(clip, m, o, cancel, progress);
    clip.fileBytes = QFileInfo(clip.papngPath).size();
    progress("미리보기 준비 완료", 1);
    return clip;
}
QImage frameImage(const Clip &c, int index, bool original) {
    if (index < 0 || index >= int(c.frames.size()))
        return {};
    QFile f(original ? c.originalPath : c.rawPath);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    auto bytes = readFrame(f, original ? c.frames[index].originalOffset : c.frames[index].offset,
                           qint64(c.width) * c.height * 4);
    return QImage(reinterpret_cast<const uchar *>(bytes.constData()), c.width, c.height,
                  QImage::Format_RGBA8888)
        .copy();
}
void save(const Clip &clip, const QString &target, const Cancel &cancel) {
    QFile source(clip.papngPath);
    require(source.open(QIODevice::ReadOnly), "변환 결과를 읽을 수 없습니다.");
    QSaveFile out(target);
    out.setDirectWriteFallback(false);
    require(out.open(QIODevice::WriteOnly), "저장 위치에 쓸 수 없습니다.");
    while (!source.atEnd()) {
        checkCancel(cancel);
        auto bytes = source.read(MiB);
        require(!bytes.isEmpty() && out.write(bytes) == bytes.size(),
                "파일 저장 실패. 기존 파일은 유지됩니다.");
    }
    checkCancel(cancel);
    require(out.commit(), "파일 교체 실패. 기존 파일은 유지됩니다.");
}
} // namespace pc
