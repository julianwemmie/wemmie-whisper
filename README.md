# wemmie-whisper

Local speech-to-text using whisper.cpp. Hold Shift+Cmd+Space to record, release to transcribe and paste.

## Prerequisites

```bash
brew install sox cmake
```

## Setup

```bash
# Clone and build whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build -j --config Release

# Download the model
sh ./models/download-ggml-model.sh base.en
cd ..
```

## Build

```bash
swiftc main.swift -o wemmie
```

## Run

```bash
./wemmie
```

On first run, macOS will ask you to grant Accessibility access in System Settings > Privacy & Security > Accessibility. Enable it for your terminal app, then restart `./wemmie`.
