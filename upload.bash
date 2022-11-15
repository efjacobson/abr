#! /bin/bash

region=
stack_name=
here="$(dirname "$(realpath "$0")")"

# shellcheck source=/dev/null
source "$here/shared.bash"

bucket=default
dry_run=true

default_aws_arguments="--region $region --profile personal"

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

set_config() {
  local outputs && outputs=$(eval "aws cloudformation describe-stacks $default_aws_arguments \
    --stack-name $stack_name \
    --query \"Stacks[0].Outputs\"")

  json_config='{'
  while read -r OutputKey; do
    read -r OutputValue
    json_config+="\"$OutputKey\":\"$OutputValue\","
  done < <(echo "$outputs" | jq -cr '.[] | (.OutputKey, .OutputValue)')
  json_config=${json_config%?}
  json_config+='}'

  echo "$json_config" >$config_file
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

  if [ ! -d "$config_file" ]; then
    set_config
  fi

  bucket_name=$(jq -r '.DefaultBucketRef' <$config_file)

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
