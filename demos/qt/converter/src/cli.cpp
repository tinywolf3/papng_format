#include "cli.h"
#include "pipeline.h"
#include <QColor>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <algorithm>
#include <cmath>
#include <csignal>

namespace pc {
namespace {
struct UsageError {
    QString message;
};
std::atomic_bool *activeCancel = nullptr;
volatile std::sig_atomic_t receivedSignal = 0;
static_assert(std::atomic_bool::is_always_lock_free, "Cancellation must be signal-safe");
void interrupted(int signal) {
    receivedSignal = signal;
    if (activeCancel)
        activeCancel->store(true);
}
void json(const QVariantMap &value) {
    QTextStream(stdout) << QJsonDocument(QJsonObject::fromVariantMap(value)).toJson(QJsonDocument::Compact)
                        << Qt::endl;
}
int usage(const QString &message) {
    QTextStream(stderr) << message << "\nUse --help for options and examples." << Qt::endl;
    return 2;
}
} // namespace

bool cliRequested(int argc, char **argv) {
    if (argc <= 1)
        return false;
    // No arguments, or just one file path, opens the wizard. Every other invocation
    // goes through the CLI parser, including short/unknown options and -v.
    return argc > 2 || QString::fromLocal8Bit(argv[1]).startsWith('-');
}

int commandLine(QCoreApplication &app) {
    QCommandLineParser parser;
    parser.setApplicationDescription(
        "Convert MP4 / WebM / GIF to PAPNG 1.1 without opening a window.\n"
        "No arguments (or a file path alone): open the GUI wizard.\n"
        "CLI defaults: whole input, original frame times, longest side <=128 pixels.\n"
        "Limits: <=60 seconds, <=512x512, <=600 frames, <=64 MiB decoded RGBA.\n\n"
        "Examples:\n"
        "  papng-converter -i animation.webm -o animation.papng\n"
        "  papng-converter animation.mp4 -o clip.papng --start 5 --duration 2 --size 64x64\n"
        "  papng-converter --info -i animation.gif\n"
        "  papng-converter --cli -i animation.gif -o result.papng --quiet\n\n"
        "stdout: one JSON result. stderr: progress/errors. Audio is not exported.");
    const auto help = parser.addHelpOption();
    const auto version = parser.addVersionOption();
    parser.addPositionalArgument("input", "Source file; alternative to -i/--input", "[input]");
    const QList<QCommandLineOption> arguments{
        {QStringList{"cli"}, "Explicitly select terminal mode"},
        {QStringList{"i", "input", "convert"}, "Source MP4, WebM or GIF (--convert is an alias)", "file"},
        {QStringList{"o", "output"}, "Output .papng file (required for conversion)", "file"},
        {QStringList{"info"}, "Print input metadata as JSON; do not convert or save"},
        {QStringList{"q", "quiet"}, "Suppress progress messages; keep the JSON result and errors"},
        {QStringList{"start"}, "Start time in seconds (default: 0)", "seconds"},
        {QStringList{"end"}, "Absolute end time in seconds (default: end of input)", "seconds"},
        {QStringList{"duration"}, "Length in seconds from --start; mutually exclusive with --end", "seconds"},
        {QStringList{"size"}, "Output pixel size, e.g. 128x96 (each dimension 1..512)", "WxH"},
        {QStringList{"crop"}, "Source rectangle, e.g. 0,0,320,240", "x,y,w,h"},
        {QStringList{"fps"}, "Resample at 1..60 FPS; 0 or omitted preserves timestamps", "number"},
        {QStringList{"colors"}, "Shared palette size 2..256; 0 preserves colors", "number"},
        {QStringList{"dither"}, "Use ordered dithering with the palette"},
        {QStringList{"smooth"}, "Use Lanczos instead of nearest-neighbor scaling"},
        {QStringList{"no-merge"}, "Keep consecutive identical frames"},
        {QStringList{"merge-tolerance"}, "Optional per-channel near-frame tolerance 0..16", "number"},
        {QStringList{"key-color"}, "Make this RGB color transparent, e.g. #00ff00", "color"},
        {QStringList{"key-tolerance"}, "Chroma key tolerance 0..255", "number"},
        {QStringList{"plays"}, "Play count 0..4294967295; 0 loops indefinitely", "number"},
        {QStringList{"overwrite"}, "Allow replacing an existing output file"}};
    parser.addOptions(arguments);
    if (!parser.parse(app.arguments()))
        return usage(parser.errorText());
    if (parser.isSet(help) || parser.isSet("help-all")) {
        QTextStream(stdout) << parser.helpText();
        return 0;
    }
    if (parser.isSet(version)) {
        QTextStream(stdout) << app.applicationName() << ' ' << app.applicationVersion() << Qt::endl;
        return 0;
    }
    auto cancel = std::make_shared<std::atomic_bool>(false);
    activeCancel = cancel.get();
    receivedSignal = 0;
    std::signal(SIGINT, interrupted);
    std::signal(SIGTERM, interrupted);
    int exitCode = 0;
    try {
        for (const auto &option : arguments)
            if (!option.valueName().isEmpty() && parser.values(option.names().first()).size() > 1)
                throw UsageError{"Specify each option only once: --" + option.names().last()};
        const auto positional = parser.positionalArguments();
        if (positional.size() > 1 || (!positional.isEmpty() && parser.isSet("input")))
            throw UsageError{"Specify exactly one source, using either -i/--input or a positional path."};
        QString input = positional.isEmpty() ? parser.value("input") : positional.first();
        if (input.isEmpty())
            throw UsageError{"A source file is required (-i input.mp4)."};
        const bool info = parser.isSet("info");
        if (info) {
            for (const auto &option : arguments) {
                const auto key = option.names().first();
                if (!QStringList{"cli", "i", "info", "q"}.contains(key) && parser.isSet(key))
                    throw UsageError{"--info cannot be combined with conversion options: --" +
                                     option.names().last()};
            }
        } else if (parser.value("output").isEmpty()) {
            throw UsageError{"An output file is required (-o result.papng)."};
        }
        if (parser.isSet("duration") && parser.isSet("end"))
            throw UsageError{"Use either --duration or --end, not both."};

        // Validate options before invoking external tools; GUI defaults stay independent.
        QVariantMap overrides;
        auto number = [&](const QString &key) {
            bool ok;
            const double value = parser.value(key).toDouble(&ok);
            if (!ok || !std::isfinite(value))
                throw UsageError{"Invalid number: --" + key};
            return value;
        };
        for (const auto &key : QStringList{"start", "end", "fps"})
            if (parser.isSet(key))
                overrides[key] = number(key);
        const double duration = parser.isSet("duration") ? number("duration") : 0;
        if (parser.isSet("duration") && duration <= 0)
            throw UsageError{"--duration must be greater than zero."};
        for (const auto &key : QStringList{"colors", "merge-tolerance", "key-tolerance", "plays"}) {
            if (!parser.isSet(key))
                continue;
            double n = number(key);
            if (n != std::floor(n) || n < 0 || n > 4294967295.0)
                throw UsageError{"Invalid integer: --" + key};
            overrides[key == "merge-tolerance" ? "mergeTolerance"
                      : key == "key-tolerance" ? "keyTolerance"
                                               : key] = n;
        }
        auto integers = [&](const QString &key, QChar delimiter, int count) {
            auto parts = parser.value(key).split(delimiter);
            if (parts.size() != count)
                throw UsageError{"Invalid --" + key};
            QList<int> result;
            for (const auto &part : parts) {
                bool ok;
                int value = part.toInt(&ok);
                if (!ok)
                    throw UsageError{"Invalid --" + key};
                result.append(value);
            }
            return result;
        };
        if (parser.isSet("size")) {
            auto v = integers("size", 'x', 2);
            overrides["width"] = v[0];
            overrides["height"] = v[1];
        }
        if (parser.isSet("crop")) {
            auto v = integers("crop", ',', 4);
            overrides["x"] = v[0];
            overrides["y"] = v[1];
            overrides["cropWidth"] = v[2];
            overrides["cropHeight"] = v[3];
        }
        overrides["dither"] = parser.isSet("dither");
        overrides["nearest"] = !parser.isSet("smooth");
        overrides["merge"] = !parser.isSet("no-merge");
        if (parser.isSet("key-color")) {
            QColor color(parser.value("key-color"));
            if (!color.isValid())
                throw UsageError{"Invalid --key-color"};
            overrides["key"] = true;
            overrides["keyColor"] = color.name();
        }
        if (parser.isSet("dither") && overrides.value("colors").toDouble() < 2)
            throw UsageError{"--dither requires --colors 2..256."};
        if (parser.isSet("key-tolerance") && !parser.isSet("key-color"))
            throw UsageError{"--key-tolerance requires --key-color."};
        if (parser.isSet("merge-tolerance") && parser.isSet("no-merge"))
            throw UsageError{"--merge-tolerance cannot be used with --no-merge."};

        QFileInfo source(input);
        QString output;
        if (!info) {
            output = QFileInfo(parser.value("output")).absoluteFilePath();
            if (!output.endsWith(".papng", Qt::CaseInsensitive))
                output += ".papng";
            QFileInfo destination(output);
            if (source.absoluteFilePath() == output ||
                (!destination.canonicalFilePath().isEmpty() &&
                 source.canonicalFilePath() == destination.canonicalFilePath()))
                throw UsageError{"The output must not replace the source."};
            if (destination.exists() && !parser.isSet("overwrite"))
                throw Error{"Output exists; use --overwrite to replace it."};
        }
        auto tools = Tools::locate();
        auto media = probe(tools, source.absoluteFilePath(), cancel);
        if (info) {
            json(media.map());
        } else {
            if (!overrides.contains("end"))
                overrides["end"] = parser.isSet("duration")
                                       ? overrides.value("start", 0).toDouble() + duration
                                       : media.duration;
            if (overrides["end"].toDouble() - overrides.value("start", 0).toDouble() > 60)
                throw UsageError{
                    "The selected range exceeds 60 seconds. Set --start and --duration (or --end)."};
            if (parser.isSet("crop") && !parser.isSet("size") && overrides["cropWidth"].toInt() > 0 &&
                overrides["cropHeight"].toInt() > 0) {
                auto cropped = media;
                cropped.width = overrides["cropWidth"].toInt();
                cropped.height = overrides["cropHeight"].toInt();
                const auto fit = Options::defaults(cropped);
                overrides["width"] = fit.width;
                overrides["height"] = fit.height;
            }
            auto options = Options::fromMap(overrides, media);
            try {
                options.validate(media);
            } catch (const Error &e) {
                throw UsageError{e.message};
            }
            QString stage;
            int lastPercent = -1;
            auto clip = convert(tools, media, options, cancel, [&](QString name, double progress) {
                if (parser.isSet("quiet"))
                    return;
                int percent = std::clamp(int(progress * 100), 0, 100);
                if (stage != name || percent >= lastPercent + 5) {
                    stage = name;
                    lastPercent = percent;
                    QTextStream(stderr) << '[' << percent << "%] " << name << Qt::endl;
                }
            });
            save(clip, output, cancel);
            auto report = clip.map();
            report["output"] = output;
            json(report);
        }
    } catch (const UsageError &e) {
        exitCode = usage(e.message);
    } catch (const Error &e) {
        QTextStream(stderr) << e.message << Qt::endl;
        exitCode = 1;
    } catch (const std::exception &e) {
        QTextStream(stderr) << e.what() << Qt::endl;
        exitCode = 1;
    }
    activeCancel = nullptr;
    return receivedSignal ? 128 + receivedSignal : exitCode;
}
} // namespace pc
