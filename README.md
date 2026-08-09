# fuse-archive.yazi (Fork)

<!--toc:start-->

- [fuse-archive.yazi (Fork)](#fuse-archiveyazi-fork)
  - [What news with this fork](#what-news-with-this-fork)
    - [Keep the file mount](#keep-the-file-mount)
    - [Support multiple deep mount](#support-multiple-deep-mount)
    - [Support mountoptions](#support-mountoptions)
    - [Exclude extensions](#exclude-extensions)
    - [Support MacOS](#support-macos)
  - [Requirements](#requirements)
  - [Installation](#installation)
    - [Dependencies:](#dependencies)
    - [fuse-archive.yazi:](#fuse-archiveyazi)
    - [Setup options](#setup-options)
  - [Key mapping](#key-mapping)
  <!--toc:end-->

<!--toc:start-->

[fuse-archive.yazi](https://github.com/boydaihungst/fuse-archive.yazi)
uses [fuse-archive](https://github.com/google/fuse-archive) to
transparently mount and unmount archives in read-only mode, allowing you to
navigate inside, view, and extract individual or groups of files.

There is another plugin on which this one is based,
[archivemount.yazi](https://github.com/AnirudhG07/archivemount.yazi). It
mounts archives with read and and write permissions. The main problem is it uses
[archivemount](https://github.com/cybernoid/archivemount) which is much slower
than [fuse-archive](https://github.com/google/fuse-archive).
It also supports very few file types compared to this plugin, and you need to
mount and unmount the archives manually.

[fuse-archive.yazi](https://github.com/boydaihungst/fuse-archive.yazi) supports mounting the following file extensions: [SUPPORTED ARCHIVE FORMATS](https://github.com/google/fuse-archive?tab=readme-ov-file#archive-formats)

## What news with this fork

> [!IMPORTANT]
> Minimum version: yazi v26.5.6.
>
> Password-protected RAR file is not supported yet!

### Keep the file mount

By using `plugin fuse-archive -- leave`. So you can copy and paste
the content to other place without open a new tab

### Support multiple deep mount

That mean, if you have a file like below,
just use the `plugin fuse-archive -- mount` to go deeper inside
and `plugin fuse-archive -- leave` to go back. Even if the files inside are password-protected,
it will still prompt you to enter a password. You only need to enter the password once for each file.

- Origin file.zip
  - Child_1.zip
    - Grandchild_1.zip
  - Child_2.zip (with password)
    - Grandchild_2.zip (with another password)
      - GranGrandchild_3.zip (with another password)

### Support mount_options

You can use `plugin fuse-archive -- mount` with mount options. Add `mount_options` option to `setup()` function.

### Exclude extensions

Using `excluded_extensions` option, you can exclude some extensions from mounting.

### Supports MacOS

This plugin supports MacOS, but you need to install `macfuse` instead of `fuse3`.

### Mount directly in virtual file system (VFS) (like sftp or trash folder)

You can mount directly in virtual file system (VFS) like sftp or trash folder.
In sftp, it will download the file to cache folder, and mount it after downloading finished.
In trash folder, it will mount the trashed file directly like normal.

## Requirements

1. [yazi](https://github.com/sxyazi/yazi).

2. This plugin only supports Linux and MacOS, and requires having latest
   [fuse-archive](https://github.com/google/fuse-archive), [xxHash](https://github.com/Cyan4973/xxHash) and `fuse3` for linux, and [macfuse](https://github.com/macfuse/macfuse/releases) for macOS installed.
   This fork requires you to build and install fuse-archive with latest
   source from github (because the latest released version in some distros is too old, 2020).

## Installation

### Dependencies:

- For Ubuntu:

  Use `libfuse3-dev` instead of `libfuse-dev` if you are using Ubuntu 22.04 or later.
  - libfuse-dev: This is for FUSE 2.x, the older version.
  - libfuse3-dev: This is for FUSE 3.x, the newer and actively developed version.
    which is recommended by fuse-archive's author.

  https://github.com/google/fuse-archive/blob/main/INSTALL.md

- For Arch based:

  ```sh
  yay -S xxhash fuse3 fuse-archive

  # or: paru -S xxhash fuse3 fuse-archive

  # Or: install fuse-archive from source:
  # git clone https://github.com/google/fuse-archive
  # cd "fuse-archive"
  # sudo make install
  ```

- For other distros, it's better to use ChatGPT for dependencies. Prompt: `install fuse-archive YOUR_DISTRO_NAME`.

- For macOS (only for fuse-archive >= v1.17):
  - You can install `macfuse` and `xxhash` with `brew install macfuse xxhash`.
  - Then install `fuse-archive`:

  ```sh
  git clone https://github.com/google/fuse-archive
  cd "fuse-archive"
  # Not tested yet, please confirm if it works.
  sudo CXXFLAGS=-DFUSE_DARWIN_ENABLE_EXTENSIONS=0 make STD=gnu++20a install
  ```

- Fuse-archive also relies on the availability of the following filter programs: `base64`, `brotli`, `compress`, `lrzip`, `lzop` and `grzip` for supporting those compression formats.

### fuse-archive.yazi:

```sh
ya pkg add boydaihungst/fuse-archive
```

Modify your `~/.config/yazi/init.lua` to include:

```lua
require("fuse-archive"):setup()
```

### Setup options

The plugin supports the following options, which can be assigned during setup:

1. (optional) `smart_enter`: If `true`, when _entering_ a file it will be _opened_, while
   directories will always be _entered_. The default value is `false`.

2. (optional) `excluded_extensions`: A list of extensions that will be excluded from mounting.

3. (optional) `extra_extensions`: A list of extensions to add to the supported mount list.
   This is useful if you want to mount an archive format that I may have missed or unawared it is supported by fuse-archive.

4. (optional) `mount_options`: String of mount options to be used when mounting the archive, separated by comma or space.
   List of options: `fuse-archive -h`

5. (optional) `mount_root_dir`: Full path of the directory where you want to mount the archive. Default is `/tmp/yazi/fuse-archive`. A subfolder with the uid will be created under this directory.

```lua
require("fuse-archive"):setup({
  smart_enter = true,
  excluded_extensions = { "deb", "apk", "rpm" },
  extra_extensions = { "xyz" },
  mount_options = "nocache,nosymlinks",
  mount_root_dir = os.getenv("HOME") .. "/abc_folder",
})
```

## Key mapping

The plugin works transparently, so for the best effect, remap your navigation
keys assigned to `enter` and `leave` to the plugin. This way you will be able
to "navigate" compressed archives as if they were part of the file system.

When you _enter_ an archive, the plugin mounts it and takes you to the mounted
directory, and when you _leave_, it won't unmount the archive but takes you back to
the original location of the archive. Normally it will unmount all mounted archive files
when you use yazi >= 25.6.11 and use `quit` command to exit yazi. Or you can use a key mapping  
of `-- unmount` action to unmount.

Add this to your `~/.config/yazi/keymap.toml`:

```toml
[mgr]
prepend_keymap = [
    { on   = [ "<Right>" ], run = "plugin fuse-archive -- mount", desc = "Enter or Mount selected archive" },
    { on   = [ "<Left>" ], run = "plugin fuse-archive -- leave", desc = "Leave selected archive without unmount it" },
    { on   = [ "l" ], run = "plugin fuse-archive -- mount", desc = "Enter or Mount selected archive" },
    { on   = [ "h" ], run = "plugin fuse-archive -- leave", desc = "Leave selected archive without unmount it" },

    # add --hide-download-notify to hide "Downloading hovered file, will auto-mount after it's finished"
    { on   = [ "l" ], run = "plugin fuse-archive -- mount --hide-download-notify", desc = "Enter or Mount selected archive" },
    { on   = [ "<Right>" ], run = "plugin fuse-archive -- mount --hide-download-notify", desc = "Enter or Mount selected archive" },

    # Over quit command for yazi <= v25.5.31 to unmount on quit. For (>=v25.12.29) yazi, you don't need to add these lines.
    { on   = [ "q" ], run = ["plugin fuse-archive -- unmount", "quit"], desc = "Quit the process" },
    { on   = [ "Q" ], run = ["plugin fuse-archive -- unmount", "quit --no-cwd-file"], desc = "Quit without outputting cwd-file" },

    # Or if you use project.yazi or other plugin that call quit command internally, just keep in mind to add unmount command before quit command.
    # Even with nightly yazi
    { on   = [ "q" ], run = ["plugin fuse-archive -- unmount", "plugin projects -- quit"], desc = "Quit the process" },
]
```

When the current file is not a supported archive type, the plugin simply calls
_enter_, and when there is nothing to unmount, it calls _leave_, so it works
transparently.

In case you run into any problems and need to unmount something manually, or
delete any temporary directories, the location of the mounts is one of the
following:

1. `/tmp/yazi/fuse-archive/...` by default.
2. Or if you set `mount_root_dir` option in `setup()` function, it will be
   `mount_root_dir/yazi/fuse-archive/...` in your `mount_root_dir` directory.
