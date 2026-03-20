# WSL Toolkit
# Source from ~/.bashrc with:
#   source /path/to/wsltoolkit.sh
# or:
#   [[ -f ~/bin/wsltoolkit.sh ]] && source ~/bin/wsltoolkit.sh
#
# Purpose:
#   Helpers for working with Windows paths inside WSL, with diagnostics when
#   a drive/share is not mounted or wslpath output is not useful.
#
# Main commands:
#   smart_wslpath 'V:\Projects'
#   wls 'V:\Projects'
#   wcd 'V:\Projects\ICON_2024\schematic'
#   pathpair 'V:\Projects'
#   wpwd
#   openhere
#   mountdrv V
#   umountdrv V
#   win2wsl 'C:\Temp'
#   wsl2win /mnt/c/Temp
#   won grep -R foo 'V:\Projects'
#   wrun notepad.exe /mnt/v/Projects/readme.txt
#
# Notes:
# - This file is intended for bash.
# - It avoids overriding the real `wslpath`; use `smart_wslpath` instead.
# - Colorized ls output is preserved by avoiding xargs.

# ----- internal helpers -----------------------------------------------------

_wtk_is_win_drive_path() {
    [[ "$1" =~ ^[A-Za-z]:\\.*$ || "$1" =~ ^[A-Za-z]:$ ]]
}

_wtk_is_unc_path() {
    [[ "$1" =~ ^\\\\.+ ]]
}

_wtk_drive_letter_lc() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

_wtk_drive_letter_uc() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

_wtk_win_rest_to_posix() {
    printf '%s' "$1" | sed 's#\\#/#g'
}

_wtk_guess_wsl_from_windows() {
    local inpath="$1"

    if [[ "$inpath" =~ ^([A-Za-z]):\\?(.*)$ ]]; then
        local drive_lc
        drive_lc="$(_wtk_drive_letter_lc "${BASH_REMATCH[1]}")"
        local rest="${BASH_REMATCH[2]}"
        local out="/mnt/${drive_lc}"
        if [[ -n "$rest" ]]; then
            out+="/$(_wtk_win_rest_to_posix "$rest")"
        fi
        printf '%s\n' "$out"
        return 0
    fi

    return 1
}

_wtk_print_mount_hint_for_drive() {
    local drive="$1"
    local inpath="$2"
    local drive_lc drive_uc guessed
    drive_lc="$(_wtk_drive_letter_lc "$drive")"
    drive_uc="$(_wtk_drive_letter_uc "$drive")"
    guessed="$(_wtk_guess_wsl_from_windows "$inpath")"

    cat >&2 <<EOF
wslpath could not produce a useful conversion for:
  $inpath

Most likely cause:
  Drive ${drive_uc}: is not mounted inside WSL.

Try this:
  sudo mkdir -p /mnt/${drive_lc}
  sudo mount -t drvfs ${drive_uc}: /mnt/${drive_lc}

Then retry:
  smart_wslpath '$inpath'

Expected WSL-style path after mounting:
  $guessed
EOF
}

_wtk_print_mount_hint_for_unc() {
    local inpath="$1"
    cat >&2 <<EOF
wslpath could not produce a useful conversion for:
  $inpath

This looks like a UNC/network path.
You may need to mount the share explicitly, for example:
  sudo mkdir -p /mnt/share
  sudo mount -t drvfs '$inpath' /mnt/share

After that, use the mounted path under /mnt/share.
EOF
}

# ----- public API -----------------------------------------------------------

# Convert Windows path -> WSL path, but with introspection and useful guidance.
# Usage:
#   smart_wslpath 'V:\Projects'
#   smart_wslpath -q 'V:\Projects'   # quiet: no diagnostics, just return/fail
# Return codes:
#   0 success
#   1 conversion failed / mount missing / inaccessible
#   2 usage error
smart_wslpath() {
    local quiet=0

    if [[ "$1" == "-q" ]]; then
        quiet=1
        shift
    fi

    local inpath="$1"
    if [[ -z "$inpath" ]]; then
        echo "Usage: smart_wslpath [-q] 'X:\\path\\to\\dir'" >&2
        return 2
    fi

    # If already a POSIX path, pass through unchanged.
    if [[ "$inpath" == /* ]]; then
        printf '%s\n' "$inpath"
        return 0
    fi

    local out rc
    out="$(wslpath -u "$inpath" 2>/dev/null)"
    rc=$?

    # Good conversion: not empty, not identical to input.
    if [[ $rc -eq 0 && -n "$out" && "$out" != "$inpath" ]]; then
        printf '%s\n' "$out"
        return 0
    fi

    # Handle drive-letter paths.
    if [[ "$inpath" =~ ^([A-Za-z]):\\?(.*)$ ]]; then
        local drive="${BASH_REMATCH[1]}"
        local drive_lc guessed base
        drive_lc="$(_wtk_drive_letter_lc "$drive")"
        base="/mnt/${drive_lc}"
        guessed="$(_wtk_guess_wsl_from_windows "$inpath")"

        # If the mountpoint exists, return guessed path even when wslpath is lame.
        if [[ -d "$base" ]]; then
            printf '%s\n' "$guessed"
            return 0
        fi

        if [[ $quiet -eq 0 ]]; then
            _wtk_print_mount_hint_for_drive "$drive" "$inpath"
        fi
        return 1
    fi

    # Handle UNC paths.
    if _wtk_is_unc_path "$inpath"; then
        if [[ $quiet -eq 0 ]]; then
            _wtk_print_mount_hint_for_unc "$inpath"
        fi
        return 1
    fi

    if [[ $quiet -eq 0 ]]; then
        cat >&2 <<EOF
wslpath could not produce a useful conversion for:
  $inpath

Either the input is not a Windows path, or WSL cannot access the backing drive/share.
EOF
    fi
    return 1
}

# Thin wrappers around the real wslpath.
win2wsl() {
    smart_wslpath "$1"
}

wsl2win() {
    wslpath -w "$1"
}

# Print a path in both forms.
pathpair() {
    local p="$1"
    if _wtk_is_win_drive_path "$p" || _wtk_is_unc_path "$p"; then
        echo "Windows: $p"
        if smart_wslpath -q "$p" >/dev/null 2>&1; then
            echo "WSL:     $(smart_wslpath -q "$p")"
        else
            echo "WSL:     [unavailable until mounted]"
        fi
    else
        echo "WSL:     $p"
        echo "Windows: $(wsl2win "$p")"
    fi
}

# ls on a Windows path, preserving color.
wls() {
    local p
    p="$(smart_wslpath -q "$1")" || {
        smart_wslpath "$1" >/dev/null
        return 1
    }
    ls --color=auto "$p"
}

# long listing variant
wll() {
    local p
    p="$(smart_wslpath -q "$1")" || {
        smart_wslpath "$1" >/dev/null
        return 1
    }
    ls -l --color=auto "$p"
}

# cd to a Windows path or POSIX path.
wcd() {
    local p
    p="$(smart_wslpath -q "$1")" || {
        smart_wslpath "$1" >/dev/null
        return 1
    }
    cd "$p" || return
}

# pwd in Windows form.
wpwd() {
    wsl2win "$PWD"
}

# Open path in Windows Explorer. Default is current directory.
openhere() {
    local p="${1:-$PWD}"
    explorer.exe "$(wsl2win "$p")" >/dev/null 2>&1
}

# Edit a Windows path using vim in WSL.
wvim() {
    local p
    p="$(smart_wslpath -q "$1")" || {
        smart_wslpath "$1" >/dev/null
        return 1
    }
    vim "$p"
}

# Run a Linux command on arguments, auto-converting Windows-looking paths.
# Example:
#   won grep -R foo 'V:\Projects'
won() {
    local cmd="$1"
    shift || true

    if [[ -z "$cmd" ]]; then
        echo "Usage: won <linux-command> [args ...]" >&2
        return 2
    fi

    local args=()
    local a conv
    for a in "$@"; do
        if _wtk_is_win_drive_path "$a" || _wtk_is_unc_path "$a"; then
            conv="$(smart_wslpath -q "$a")" || {
                smart_wslpath "$a" >/dev/null
                return 1
            }
            args+=("$conv")
        else
            args+=("$a")
        fi
    done

    "$cmd" "${args[@]}"
}

# Run a Windows command on arguments, auto-converting POSIX-looking paths.
# Example:
#   wrun notepad.exe /mnt/v/Projects/readme.txt
wrun() {
    local cmd="$1"
    shift || true

    if [[ -z "$cmd" ]]; then
        echo "Usage: wrun <windows-command.exe> [args ...]" >&2
        return 2
    fi

    local args=()
    local a
    for a in "$@"; do
        if [[ "$a" == /* ]]; then
            args+=("$(wsl2win "$a")")
        else
            args+=("$a")
        fi
    done

    "$cmd" "${args[@]}"
}

# Mount a Windows drive letter under /mnt/<letter>.
# Example:
#   mountdrv V
mountdrv() {
    local d="$1"
    if [[ -z "$d" || ! "$d" =~ ^[A-Za-z]$ ]]; then
        echo "Usage: mountdrv <drive-letter>" >&2
        return 2
    fi
    local dl du
    dl="$(_wtk_drive_letter_lc "$d")"
    du="$(_wtk_drive_letter_uc "$d")"
    sudo mkdir -p "/mnt/$dl"
    sudo mount -t drvfs "${du}:" "/mnt/$dl"
}

# Unmount a drive from /mnt/<letter>.
umountdrv() {
    local d="$1"
    if [[ -z "$d" || ! "$d" =~ ^[A-Za-z]$ ]]; then
        echo "Usage: umountdrv <drive-letter>" >&2
        return 2
    fi
    local dl
    dl="$(_wtk_drive_letter_lc "$d")"
    sudo umount "/mnt/$dl"
}

# Check whether /mnt/<letter> exists.
hasdrv() {
    local d="$1"
    if [[ -z "$d" || ! "$d" =~ ^[A-Za-z]$ ]]; then
        echo "Usage: hasdrv <drive-letter>" >&2
        return 2
    fi
    local dl
    dl="$(_wtk_drive_letter_lc "$d")"
    [[ -d "/mnt/$dl" ]]
}

# Normalize all arguments that look like Windows paths into WSL paths.
normalize_args() {
    local a conv
    for a in "$@"; do
        if _wtk_is_win_drive_path "$a" || _wtk_is_unc_path "$a"; then
            conv="$(smart_wslpath -q "$a")" || {
                smart_wslpath "$a" >/dev/null
                return 1
            }
            echo "$conv"
        else
            echo "$a"
        fi
    done
}

# Quick help.
wsltoolkit_help() {
    cat <<'EOF'
WSL Toolkit commands:

  smart_wslpath 'V:\Projects'
      Convert Windows path to WSL path.
      If conversion is not useful, print mount instructions.

  win2wsl 'C:\Temp'
  wsl2win /mnt/c/Temp
      Simple path conversions.

  wls 'V:\Projects'
  wll 'V:\Projects'
      Colorized ls on Windows paths.

  wcd 'V:\Projects\ICON_2024\schematic'
      cd using a Windows path.

  wpwd
      Print current directory in Windows form.

  openhere [path]
      Open a path in Windows Explorer.

  won <linux-cmd> [args...]
      Run Linux command, auto-converting Windows path arguments.

  wrun <windows-cmd.exe> [args...]
      Run Windows command, auto-converting POSIX path arguments.

  mountdrv V
  umountdrv V
  hasdrv V
      Manage/check drive mounts.

  pathpair <path>
      Print both Windows and WSL forms.
EOF
}

# Optional convenience aliases. Comment out if you do not want them.
alias whelp='wsltoolkit_help'

# End of wsltoolkit.sh
