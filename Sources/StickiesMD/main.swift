import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    do {
        try Snapshot.run(to: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
        exit(1)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
