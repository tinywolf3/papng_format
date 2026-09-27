#pragma once
class QCoreApplication;
namespace pc {
// Dispatch before creating QGuiApplication so even invalid CLI arguments are headless.
bool cliRequested(int argc, char **argv);
int commandLine(QCoreApplication &app);
} // namespace pc
