#! /bin/bash

dry_run=true
volatile=true
stack_name=abr

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --dryrun flag
  --hot         Equivalent to --dry-run=false
  --volatile    Upload to the volatile bucket
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
    --hot)
      dry_run=false
      ;;
    --volatile=*)
      if [ 'false' == "${opt#*=}" ]; then
        volatile=false
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
}

main() {
  if [ '' == "$src" ]; then
    echo 'a path to the src is required'
    exit
  fi

  if [ ! -f "$src" ]; then
    echo 'src is not a file'
    exit
  fi

  if ! $volatile; then
    echo 'non-volatile uploads are not currently supported'
    exit
  fi

  volatile_bucket=$(yq -r '.VolatileBucketName' <".$stack_name-stack-outputs.yaml")

  if [ 'null' == "$volatile_bucket" ]; then
    echo 'unable to determine bucket name'
    exit
  fi

  dest="s3://$volatile_bucket"
  cmd="aws s3 cp $src $dest/$src --profile personal"

  if $dry_run; then
    cmd+=' --dryrun'
  fi

  eval "$cmd"
}

src="$1"
shift
parse_arguments "$@"

main
