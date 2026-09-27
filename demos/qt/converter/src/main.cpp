#include "cli.h"
#include "controller.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

int main(int argc, char **argv) {
    QCoreApplication::setApplicationName("papng-converter");
    QCoreApplication::setApplicationVersion(PAPNG_CONVERTER_VERSION);
    QCoreApplication::setOrganizationName("PAPNG");
    if (pc::cliRequested(argc, argv)) {
        QCoreApplication app(argc, argv);
        return pc::commandLine(app);
    }
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Fusion");
    auto *images = new Images;
    Controller controller(images);
    QQmlApplicationEngine engine;
    engine.addImageProvider("frames", images);
    engine.setInitialProperties({{"controller", QVariant::fromValue(&controller)}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); },
        Qt::QueuedConnection);
    engine.loadFromModule("PapngConverter", "Main");
    if (argc > 1)
        controller.open(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    return app.exec();
}
