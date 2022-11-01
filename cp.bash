#! /bin/bash

source="$1"
dry_run=true
shift

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka --dryrun
  --help        This message
"
}

for opt in "$@"; do
  case ${opt} in
  --dry-run=*)
    if [ 'false' == "${opt#*=}" ]; then
      dry_run=false
    fi
    ;;
  --help)
    display_help
    exit
    ;;
  *)
    display_help
    exit
    ;;
  esac
done

main() {
  if [ '' == "$source" ]; then
    echo 'you must enter a file name'
    exit 1
  fi

  if [ -d "$source" ]; then
    echo "$source is a directory, this is not yet supported"
    exit 1
  fi

  if [ ! -f "$source" ]; then
    echo "$source is not a file"
    exit 1
  fi

  local options=' '
  if [ "$dry_run" == true ]; then
    options+='--dry-run '
  fi

  echo "$source $options"
}

main
