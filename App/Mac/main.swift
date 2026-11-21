import AppKit
import Shell

#if DEBUG
// Demo and snapshot runs never write the person's own prefs: `UserDefaults.standard` is a throwaway suite for them.
UserDefaults.useThrowawayForDebugRuns()
#endif

// The app has two modes (E9-6): the normal app, and `--background-collect`, which launchd starts from the collector agent to run
// the Mac collectors with no window while the app is quit.
if CommandLine.arguments.contains(BackgroundCollector.flag) {
    MainActor.assumeIsolated { BackgroundCollector.run() }
} else {
    AinkradCoreApp.main()
}
