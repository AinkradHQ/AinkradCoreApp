import AppKit

// The app has two modes (E9-6): the normal app, and `--background-collect`, which launchd starts from the collector agent to run
// the Mac collectors with no window while the app is quit.
if CommandLine.arguments.contains(BackgroundCollector.flag) {
    MainActor.assumeIsolated { BackgroundCollector.run() }
} else {
    AinkradCoreApp.main()
}
