#! /bin/bash

here="$(dirname "$(realpath "$0")")"
bucket=default
dry_run=true
profile=

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --dryrun flag
  --hot         Equivalent to --dry-run=false
  --bucket      The bucket to upload to
  --help        This message
"
}

parse_arguments() {
  for opt in "$@"; do
    case ${opt} in
    --dry-run=*)
      if [ 'false' == "${opt#*=}" ]; then
        dry_run=false
      fi
      ;;
    --stack=*)
      stack="${opt#*=}"
      ;;
    --hot)
      dry_run=false
      ;;
    --bucket=*)
      bucket="${opt#*=}"
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
}

main() {
  if ! [ -x "$(command -v jq)" ]; then
    echo 'exiting early: jq not installed'
    exit
  fi

  if [ '' == "$src" ]; then
    echo 'a path to the src is required'
    exit
  fi

  if [ ! -f "$src" ]; then
    echo 'src is not a file'
    exit
  fi

  if [ 'default' != "$bucket" ]; then
    echo 'non-default uploads are not currently supported'
    exit
  fi

  # shellcheck source=/dev/null
  source "$here/shared.bash" "$stack"

  bucket_name=$(get_bucket_name 'Default')

  if [ 'null' == "$bucket_name" ]; then
    echo 'unable to determine bucket name'
    exit
  fi

  dest="s3://$bucket_name"
  cmd="aws s3 cp $src $dest/$src --profile $profile"

  if $dry_run; then
    cmd+=' --dryrun'
  fi

  eval "$cmd"
}

src="$1"
shift
parse_arguments "$@"

main
