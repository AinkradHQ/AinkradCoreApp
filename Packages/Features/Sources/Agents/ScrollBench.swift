/// Debug switches for the scroll benchmark (`CORE_SCROLL_BENCH`): parts of the session screen to leave out, so their cost
/// on scrolling can be measured one at a time. Empty in normal runs.
public enum ScrollBench {
    nonisolated(unsafe) public static var off: Set<String> = []
}
