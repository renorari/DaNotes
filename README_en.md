# DaNotes

日本語はこちら: [README.md](./README.md)

![DaNotes](./assets/danotes.svg)

DaNotes is a real-time Markdown editor app for Mac built with SwiftUI.  
Markdown text entered in the left text editor is previewed in real-time on the right side.

## Features

- **Real-time Preview**: Markdown text entered in the left editor is instantly rendered on the right side
- **Data Persistence**: Entered text is automatically saved and persists even after app restart
- **Clear Function**: Text can be cleared using the rubbish bin button in the toolbar or Cmd+Delete key
- **Beautiful UI**: Clean interface designed to match macOS native design

## Technical Specifications

- **Programming Language**: Swift
- **Framework**: SwiftUI
- **Supported OS**: macOS 26 or later
- **External Libraries**:
  - [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) - Markdown rendering

## Screenshots

![App Screenshot](./assets/screenshot.png)

The app features a split layout:

- Left side: Text editor (Markdown input)
- Right side: Preview area (rendered output)

## Usage

1. Launch the app
2. Enter Markdown text in the left editor
3. View the instant preview on the right side
4. To clear text, click the rubbish bin button in the toolbar or press Cmd+Delete

## Build Instructions

### Requirements

- Xcode 26 or later
- macOS 26 or later

### Build Steps

1. Clone this repository:

```bash
git clone https://github.com/renorari/DaNotes.git
cd DaNotes
```

2. Open `DaNotes.xcodeproj` in Xcode

3. Build and run the project (Cmd+R)

## Developer

Created by: Renorari  
Created on: 3rd July 2025

## Licence

This project is licenced under the GNU GENERAL PUBLIC LICENSE Version 3.  
See the [LICENCE](./LICENCE) file for details.

## Contributing

Bug reports and feature requests are welcome on the GitHub Issues page.
