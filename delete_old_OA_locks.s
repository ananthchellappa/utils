#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  delete_old_oa_locks.sh -preview USERNAME
  delete_old_oa_locks.sh -force   USERNAME
  delete_old_oa_locks.sh -help

Description:
  Finds files matching:

      *.oa.cdslck

  older than 720 days, and deletes only those containing USERNAME.

Options:
  -preview   Show files that would be deleted, but do not delete them
  -force     Actually delete matching files
  -help      Show this help message

Examples:
  ./delete_old_oa_locks.sh -preview ananth
  ./delete_old_oa_locks.sh -force   ananth
EOF
}

if [[ $# -eq 0 ]]; then
    echo "ERROR: Must specify either -preview or -force."
    echo
    usage
    exit 1
fi

mode="$1"

case "$mode" in
    -help|--help)
        usage
        exit 0
        ;;
    -preview)
        action="preview"
        ;;
    -force)
        action="force"
        ;;
    *)
        echo "ERROR: First argument must be -preview, -force, or -help."
        echo
        usage
        exit 1
        ;;
esac

if [[ $# -ne 2 ]]; then
    echo "ERROR: USERNAME argument is required."
    echo
    usage
    exit 1
fi

username="$2"

if [[ -z "$username" ]]; then
    echo "ERROR: USERNAME cannot be empty."
    exit 1
fi

count=0

find . -type f -name '*.oa.cdslck' -mmin +720 -print0 |
while IFS= read -r -d '' file; do
    if grep -qF -- "$username" "$file"; then
        count=$((count + 1))

        if [[ "$action" == "preview" ]]; then
            echo "Would delete: $file"
        else
            echo "Deleting: $file"
            rm -- "$file"
        fi
    fi
done
