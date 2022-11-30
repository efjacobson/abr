#! /bin/bash

stack_name=
profile=
region=
here="$(dirname "$(realpath "$0")")"

display_help() {
  echo "
Available options:
  --stack
  --help        This message
"
}

parse_arguments() {
  for opt in "$@"; do
    case ${opt} in
    --stack=*)
      stack="${opt#*=}"
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
  local -r termination_error=$(aws cloudformation update-termination-protection --no-enable-termination-protection --stack-name "$stack_name" --region "$region" --profile "$profile" 2>&1 1>/dev/null | sed '/^$/d')
  if [ -n "$termination_error" ]; then
    echo "$termination_error"
    exit
  fi
  local -r empty_error=$("$here"/empty-buckets.bash --bucket=all --stack="$stack" --hot 2>&1 1>/dev/null | sed '/^$/d')
  if [ -n "$empty_error" ]; then
    echo "$empty_error"
    exit
  fi
  local -r delete_error=$(aws cloudformation delete-stack --stack-name "$stack_name" --region "$region" --profile "$profile" 2>&1 1>/dev/null | sed '/^$/d')
  if [ -n "$delete_error" ]; then
    echo "$delete_error"
    exit
  fi

  while read -r failed; do
    aws cloudformation delete-stack --stack-name "$failed" --region "$region" --profile "$profile"
  done < <(aws cloudformation list-stacks --region "$region" --profile "$profile" --stack-status-filter DELETE_FAILED | jq -r '.StackSummaries[] | .StackName')
}

parse_arguments "$@"
# shellcheck source=/dev/null
source "$here/shared.bash" "$stack"
main
