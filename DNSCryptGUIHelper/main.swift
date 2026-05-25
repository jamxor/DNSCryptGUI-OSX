import Foundation

// launchd execs the helper binary. We set up the XPC listener and park the
// main thread on a run loop. Launchd handles idle-timeout and restart
// policy per the helper's launchd plist.
let tool = HelperTool()
tool.run()
