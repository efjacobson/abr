#! /bin/bash

bucket=default
default_aws_arguments=
dry_run=true
here="$(dirname "$(realpath "$0")")"
stack_name=

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
  if ! [ -x "$(command -v jq)" ]; then
    echo 'exiting early: jq not installed'
    exit
  fi

  # shellcheck source=/dev/null
  source "$here/shared.bash"

  local buckets && buckets=$(eval "aws cloudformation list-stack-resources --stack-name $stack_name $default_aws_arguments" | jq -r '.StackResourceSummaries[] | select(.ResourceType == "AWS::S3::Bucket") | .PhysicalResourceId')

  local rm_command
  for bucket in $buckets; do
    rm_command="aws s3 rm s3://$bucket --recursive --profile personal"
    if $dry_run; then
      rm_command+=' --dryrun'
    fi
    eval "$rm_command"
  done
}

parse_arguments "$@"
main
