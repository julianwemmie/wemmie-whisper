import Foundation
import CoreGraphics

let home = FileManager.default.homeDirectoryForCurrentUser.path
let whisperCli = "\(home)/Documents/code/fractal-tech/Week 6/wemmie-whisper/whisper.cpp/build/bin/whisper-cli"
let modelPath = "\(home)/Documents/code/fractal-tech/Week 6/wemmie-whisper/whisper.cpp/models/ggml-base.en.bin"
let audioPath = "/tmp/wemmie-audio.wav"
let recPath = "/opt/homebrew/bin/rec"

var recordingProcess: Process?
var isRecording = false
var eventTap: CFMachPort?

func startRecording() {
    guard !isRecording else { return }
    isRecording = true

    try? FileManager.default.removeItem(atPath: audioPath)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: recPath)
    process.arguments = [audioPath, "rate", "16k", "channels", "1"]
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        recordingProcess = process
        print("Recording...")
    } catch {
        print("Failed to start recording: \(error)")
        isRecording = false
    }
}

func stopAndTranscribe() {
    guard isRecording, let process = recordingProcess else { return }
    isRecording = false

    process.terminate()
    process.waitUntilExit()
    recordingProcess = nil
    print("Transcribing...")

    let whisper = Process()
    let pipe = Pipe()
    whisper.executableURL = URL(fileURLWithPath: whisperCli)
    whisper.arguments = ["-m", modelPath, "-f", audioPath, "--no-timestamps"]
    whisper.standardOutput = pipe
    whisper.standardError = FileHandle.nullDevice

    do {
        try whisper.run()
        whisper.waitUntilExit()
    } catch {
        print("Transcription failed: \(error)")
        return
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else {
        print("No transcription result.")
        return
    }

    print("Transcribed: \(text)")

    let pbcopy = Process()
    let pbInput = Pipe()
    pbcopy.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    pbcopy.standardInput = pbInput

    do {
        try pbcopy.run()
        pbInput.fileHandleForWriting.write(text.data(using: .utf8)!)
        pbInput.fileHandleForWriting.closeFile()
        pbcopy.waitUntilExit()
    } catch {
        print("Clipboard copy failed: \(error)")
        return
    }

    let paste = Process()
    paste.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    paste.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]

    do {
        try paste.run()
        paste.waitUntilExit()
        print("Done!")
    } catch {
        print("Paste failed: \(error)")
    }
}

func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    if keyCode == 49 && type == .keyDown && flags.contains(.maskShift) && flags.contains(.maskCommand) {
        if !isRecording {
            startRecording()
        } else {
            DispatchQueue.global().async {
                stopAndTranscribe()
            }
        }
        return nil
    }

    return Unmanaged.passRetained(event)
}

let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: eventCallback,
    userInfo: nil
) else {
    print("Failed to create event tap.")
    print("Enable Accessibility access in System Settings > Privacy & Security > Accessibility")
    exit(1)
}

eventTap = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("Wemmie Whisper running. Press Shift+Cmd+Space to record, release to transcribe.")
print("Ctrl+C to quit.")

CFRunLoopRun()
