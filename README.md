# wise: Automatic window resizer for macOS

This is currently just for me because I want to automatically pin apps to have specific border insets.
Thus, the border insets are not configurable -- they will always be 8, 8, 6, 8 beecause those look best on my system.
**It's also probably very buggy.**

## Usage

First, clone:

```shell
git clone https://github.com/ethanuppal/wise.git
cd wise
```

Then, run:

```shell
swift run -c release wise <bundle ids>
```

For example:

```shell
swift run -c release wise com.apple.Safari net.kovidgoyal.kitty
```
