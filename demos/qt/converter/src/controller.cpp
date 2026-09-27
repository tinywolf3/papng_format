#include "controller.h"
#include <QDesktopServices>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QMutexLocker>
#include <QtConcurrent>
#include <algorithm>

QImage Images::requestImage(const QString &id, QSize *size, const QSize &) {
    QMutexLocker lock(&mutex);
    auto image = images.value(id.section('?', 0, 0));
    if (size)
        *size = image.size();
    return image;
}
void Images::set(const QString &id, const QImage &image) {
    QMutexLocker lock(&mutex);
    images[id] = image;
}
Controller::Controller(Images *images, QObject *parent)
    : QObject(parent), m_images(images), m_tools(pc::Tools::locate()) {
    connect(&m_watcher, &QFutureWatcher<Job>::finished, this, [this] {
        auto result = m_watcher.result();
        m_busy = false;
        if (!result.error.isEmpty()) {
            m_error = result.error;
            m_status = m_cancel->load() ? "취소됨" : "처리하지 못했습니다.";
        } else if (m_done)
            m_done(std::move(result));
        m_done = {};
        emit changed();
    });
}
Controller::~Controller() {
    m_cancel->store(true);
    m_watcher.waitForFinished();
}
void Controller::start(Work work, std::function<void(Job)> done) {
    if (m_busy)
        return;
    m_busy = true;
    m_error.clear();
    m_progress = 0;
    m_status = "준비 중";
    m_done = std::move(done);
    m_cancel = std::make_shared<std::atomic_bool>(false);
    emit changed();
    auto cancel = m_cancel;
    auto report = [this, timer = QElapsedTimer{}](QString stage, double value) mutable {
        if (timer.isValid() && timer.elapsed() < 60 && value < 1)
            return;
        timer.start();
        QMetaObject::invokeMethod(
            this,
            [this, stage, value] {
                m_status = stage;
                m_progress = value;
                emit changed();
            },
            Qt::QueuedConnection);
    };
    m_watcher.setFuture(QtConcurrent::run([work = std::move(work), cancel, report]() mutable {
        try {
            return work(cancel, report);
        } catch (const pc::Error &e) {
            Job result;
            result.error = e.message;
            return result;
        } catch (const std::exception &e) {
            Job result;
            result.error = "처리 중 오류: " + QString::fromUtf8(e.what());
            return result;
        }
    }));
}
void Controller::invalidate() {
    m_clip = {};
    m_images->set("result", {});
    m_images->set("original", {});
    m_resultUrl.clear();
    m_originalUrl.clear();
    m_savedPath.clear();
    m_index = 0;
    emit frameChanged();
}
void Controller::setSource(const QImage &image, double time) {
    m_images->set("source", image);
    m_sourceUrl = "image://frames/source?" + QString::number(++m_revision);
    m_sourceTime = time;
}
void Controller::open(const QUrl &url) {
    if (m_busy || !url.isLocalFile())
        return;
    auto path = url.toLocalFile();
    auto tools = m_tools;
    start(
        [tools, path](const pc::Cancel &c, const pc::Progress &p) {
            p("영상 정보와 첫 프레임 읽기", 0.1);
            Job j;
            j.media = pc::probe(tools, path, c);
            j.image = pc::thumbnail(tools, j.media, 0, c);
            return j;
        },
        [this](Job j) {
            m_media = j.media;
            m_settings = pc::Options::defaults(m_media).map();
            invalidate();
            setSource(j.image, 0);
            m_status = "구간과 출력 크기를 선택하세요.";
        });
}
void Controller::change(const QString &key, const QVariant &value) {
    if (m_busy || !m_settings.contains(key) || m_settings[key] == value)
        return;
    m_settings[key] = value;
    invalidate();
    m_error.clear();
    emit changed();
}
void Controller::crop(int x, int y, int width, int height) {
    if (m_busy || !m_media.width)
        return;
    m_settings["x"] = x;
    m_settings["y"] = y;
    m_settings["cropWidth"] = width;
    m_settings["cropHeight"] = height;
    invalidate();
    emit changed();
}
void Controller::seek(double time) {
    if (m_busy || !m_media.width)
        return;
    time = std::clamp(time, 0.0, std::max(0.0, m_media.duration - 0.000001));
    auto media = m_media;
    auto tools = m_tools;
    start(
        [tools, media, time](const pc::Cancel &c, const pc::Progress &) {
            Job j;
            j.image = pc::thumbnail(tools, media, time, c);
            j.time = time;
            return j;
        },
        [this](Job j) {
            setSource(j.image, j.time);
            m_status = "원본 프레임";
        });
}
void Controller::step(int direction) {
    if (m_busy || !m_media.width)
        return;
    auto media = m_media;
    auto tools = m_tools;
    auto time = m_sourceTime;
    start(
        [tools, media, time, direction](const pc::Cancel &c, const pc::Progress &) {
            Job j;
            j.time = pc::adjacentTime(tools, media, time, direction, c);
            j.image = pc::thumbnail(tools, media, j.time, c);
            return j;
        },
        [this](Job j) {
            setSource(j.image, j.time);
            m_status = "원본 프레임";
        });
}
void Controller::generate() {
    if (m_busy || !m_media.width)
        return;
    auto media = m_media;
    auto options = pc::Options::fromMap(m_settings, media);
    auto tools = m_tools;
    start(
        [tools, media, options](const pc::Cancel &c, const pc::Progress &p) {
            Job j;
            j.clip = pc::convert(tools, media, options, c, p);
            return j;
        },
        [this](Job j) {
            m_clip = std::move(j.clip);
            m_savedPath.clear();
            selectFrame(0);
            m_progress = 1;
            m_status = "미리보기를 확인하고 저장하세요.";
            emit generated();
        });
}
int Controller::frameDelay() const {
    return ready() ? std::max(1, int((m_clip.frames[m_index].durationUs + 500) / 1000)) : 100;
}
void Controller::selectFrame(int index) {
    if (!ready())
        return;
    m_index = std::clamp(index, 0, frameCount() - 1);
    try {
        m_images->set("result", pc::frameImage(m_clip, m_index));
        m_images->set("original", pc::frameImage(m_clip, m_index, true));
    } catch (const pc::Error &e) {
        m_error = e.message;
    }
    auto suffix = QString::number(++m_revision);
    m_resultUrl = "image://frames/result?" + suffix;
    m_originalUrl = "image://frames/original?" + suffix;
    emit frameChanged();
    emit changed();
}
void Controller::exportFile(const QUrl &url) {
    if (m_busy || !ready() || !url.isLocalFile())
        return;
    auto path = url.toLocalFile();
    if (!path.endsWith(".papng", Qt::CaseInsensitive)) {
        m_error = "파일 이름의 확장자를 .papng로 지정하세요.";
        emit changed();
        return;
    }
    if (QFileInfo(path).absoluteFilePath() == QFileInfo(m_media.path).absoluteFilePath() ||
        (!QFileInfo(path).canonicalFilePath().isEmpty() &&
         QFileInfo(path).canonicalFilePath() == QFileInfo(m_media.path).canonicalFilePath())) {
        m_error = "원본 파일과 다른 저장 위치를 선택하세요.";
        emit changed();
        return;
    }
    auto clip = m_clip;
    start(
        [clip, path](const pc::Cancel &c, const pc::Progress &p) {
            p("PAPNG 저장", 0.5);
            pc::save(clip, path, c);
            Job j;
            j.path = path;
            return j;
        },
        [this](Job j) {
            m_savedPath = j.path;
            m_status = "저장 완료: " + QFileInfo(j.path).fileName();
            m_progress = 1;
        });
}
void Controller::cancel() {
    if (m_busy) {
        m_cancel->store(true);
        m_status = "취소 중";
        emit changed();
    }
}
void Controller::reveal() {
    if (!m_savedPath.isEmpty())
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(m_savedPath).absolutePath()));
}
QUrl Controller::suggestedOutput() const {
    return QUrl::fromLocalFile(
        QFileInfo(m_media.path).dir().filePath(QFileInfo(m_media.path).completeBaseName() + ".papng"));
}
