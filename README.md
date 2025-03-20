# wise: Automatic window resizer for macOS

This is currently just for me because I want to automatically pin apps to have specific border insets.
Thus, the border insets are not configurable -- they will always be 8, 8, 6, 8 beecause those look best on my system.

## Usage

```shell
swift run -c release wise <bundle ids>
```

For example:

```shell
swift run -c release wise com.apple.Safari net.kovidgoyal.kitty
```

## Issues

- When an app is killed, it won't automatically be detected when it's reopened.
