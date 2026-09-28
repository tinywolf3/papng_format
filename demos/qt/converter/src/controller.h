#pragma once
#include "pipeline.h"
#include <QFutureWatcher>
#include <QCache>
#include <QColor>
#include <QMutex>
#include <QObject>
#include <QQuickImageProvider>
#include <QUrl>

class Images final : public QQuickImageProvider {
  public:
    Images() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &, QSize *, const QSize &) override;
    void set(const QString &, const QImage &);

  private:
    QMutex mutex;
    QHash<QString, QImage> images;
};

class Controller final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap media READ media NOTIFY changed)
    Q_PROPERTY(QVariantMap settings READ settings NOTIFY changed)
    Q_PROPERTY(QVariantMap result READ result NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool comparisonBusy READ comparisonBusy NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(double progress READ progress NOTIFY changed)
    Q_PROPERTY(double sourceTime READ sourceTime NOTIFY changed)
    Q_PROPERTY(QString sourceUrl READ sourceUrl NOTIFY changed)
    Q_PROPERTY(QString resultUrl READ resultUrl NOTIFY changed)
    Q_PROPERTY(QString originalUrl READ originalUrl NOTIFY changed)
    Q_PROPERTY(int frameIndex READ frameIndex NOTIFY frameChanged)
    Q_PROPERTY(int frameCount READ frameCount NOTIFY changed)
    Q_PROPERTY(int frameDelay READ frameDelay NOTIFY frameChanged)
    Q_PROPERTY(QString savedPath READ savedPath NOTIFY changed)
  public:
    explicit Controller(Images *images, QObject *parent = nullptr);
    ~Controller() override;
    QVariantMap media() const { return m_media.width ? m_media.map() : QVariantMap{}; }
    QVariantMap settings() const { return m_settings; }
    QVariantMap result() const { return m_clip.map(); }
    bool busy() const { return m_busy; }
    bool comparisonBusy() const { return m_comparisonBusy; }
    bool ready() const { return !m_clip.frames.empty(); }
    QString status() const { return m_status; }
    QString error() const { return m_error; }
    double progress() const { return m_progress; }
    double sourceTime() const { return m_sourceTime; }
    QString sourceUrl() const { return m_sourceUrl; }
    QString resultUrl() const { return m_resultUrl; }
    QString originalUrl() const { return m_originalUrl; }
    int frameIndex() const { return m_index; }
    int frameCount() const { return int(m_clip.frames.size()); }
    int frameDelay() const;
    QString savedPath() const { return m_savedPath; }
    Q_INVOKABLE void open(const QUrl &);
    Q_INVOKABLE void change(const QString &, const QVariant &);
    Q_INVOKABLE void crop(int x, int y, int width, int height);
    Q_INVOKABLE void seek(double);
    Q_INVOKABLE QColor sourceColor(int x, int y) const;
    Q_INVOKABLE void step(int);
    Q_INVOKABLE void generate();
    Q_INVOKABLE void selectFrame(int);
    Q_INVOKABLE void exportFile(const QUrl &);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reveal();
    Q_INVOKABLE QUrl suggestedOutput() const;
  signals:
    void changed();
    void frameChanged();
    void generated();

  private:
    struct Job {
        pc::Media media;
        pc::Clip clip;
        QImage image;
        double time = 0;
        QString error, path;
    };
    using Work = std::function<Job(const pc::Cancel &, const pc::Progress &)>;
    void start(Work, std::function<void(Job)>);
    void invalidate();
    void setSource(const QImage &, double);
    void requestOriginal();
    void publishComparison(const QImage &);
    QImage m_sourceImage;
    QCache<int, QImage> m_originalCache{128 * 1024};
    QFutureWatcher<Job> m_originalWatcher;
    pc::Cancel m_originalCancel = std::make_shared<std::atomic_bool>(false);
    bool m_comparisonBusy = false, m_fetchPending = false;
    int m_generation = 0, m_fetchGeneration = 0, m_fetchIndex = 0;
    Images *m_images;
    pc::Tools m_tools;
    pc::Media m_media;
    pc::Clip m_clip;
    QVariantMap m_settings;
    QFutureWatcher<Job> m_watcher;
    pc::Cancel m_cancel = std::make_shared<std::atomic_bool>(false);
    std::function<void(Job)> m_done;
    bool m_busy = false;
    QString m_status = "파일을 선택하면 시작합니다.", m_error, m_sourceUrl, m_resultUrl, m_originalUrl,
            m_savedPath;
    double m_progress = 0, m_sourceTime = 0;
    int m_index = 0, m_revision = 0;
};
