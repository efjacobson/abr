#! /bin/bash

dry_run=true
bucket=default
stack_name=abr

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

  bucket_name=$(yq -r '.DefaultBucketName' <".$stack_name-stack-outputs.yaml")

  if [ 'null' == "$bucket_name" ]; then
    echo 'unable to determine bucket name'
    exit
  fi

  dest="s3://$bucket_name"
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
