#! /usr/bin/env bash

bucket='default'
dry_run=true
profile=
region=
here="$(dirname "$(realpath "$0")")"

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --dryrun flag
  --hot         Equivalent to --dry-run=false
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
    --bucket=*)
      bucket="${opt#*=}"
      ;;
    --hot)
      dry_run=false
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
  local buckets=()
  if [ 'all' != "$bucket" ]; then
    buckets+=("$account_id-$stack_name-$bucket")
  else
    for b in $(eval "aws cloudformation list-stack-resources --stack-name $stack_name --region $region --profile $profile" | jq -r '.StackResourceSummaries[] | select(.ResourceType == "AWS::S3::Bucket") | .PhysicalResourceId'); do
      buckets+=("$b")
    done
  fi

  local rm_command
  for bucket in "${buckets[@]}"; do
    rm_command="aws s3 rm s3://$bucket --recursive --profile $profile"
    if $dry_run; then
      rm_command+=' --dryrun'
    fi
    eval "$rm_command"
  done
}

parse_arguments "$@"
# shellcheck source=/dev/null
source "$here/shared.bash" "$stack"
main
