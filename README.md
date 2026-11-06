# CmdTab

Offline macOS window switcher with window previews. Uses ⌘Tab by default.

## Install

Needs macOS 12+ and Xcode 26+.

```sh
xcodebuild -project CmdTab.xcodeproj -scheme Release -derivedDataPath build.noindex
osascript -e 'quit app "CmdTab"'
rm -rf /Applications/CmdTab.app
cp -R build.noindex/Build/Products/Release/CmdTab.app /Applications/
open /Applications/CmdTab.app
```

Grant Accessibility and Screen Recording when asked.
