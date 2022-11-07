#! /bin/bash

dry_run=true
json_config=
region=us-east-1
stack_name=abr

config_file="./.$stack_name-stack-outputs.json"
default_aws_arguments="--region $region --profile personal"

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --no-execute-changeset flag
  --hot         Equivalent to --dry-run=false
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

deploy_stack() {
  local deploy_command="aws cloudformation deploy --template-file ./infra.yaml --stack-name $stack_name $default_aws_arguments"
  if $dry_run; then
    deploy_command+=' --no-execute-changeset'
  fi

  local deploy_output && deploy_output=$(eval "$deploy_command")
  echo "$deploy_output" | bat
  local ultimate_line && ultimate_line=$(echo "$deploy_output" | tail -n1)
  if [ "No changes to deploy. Stack $stack_name is up to date" == "$ultimate_line" ]; then
    return
  fi

  if $dry_run; then
    local describe_command="$ultimate_line $default_aws_arguments"
    printf '\n%s\n\n' 'dry run, change set description:'
    local describe_output && describe_output=$(eval "$describe_command")
    echo "$describe_output" | bat
    return
  fi

  set_config
}

get_lambda_bucket_name() {
  if [ '' == "$json_config" ]; then
    if [ -f $config_file ]; then
      json_config=$(jq <$config_file)
    else
      set_config
    fi
  fi
  echo "$json_config" | jq -r '.LambdaFunctionBucketName'
}

upload_lambda_function_zips() {
  local workdir && workdir="$(mktemp -d)"
  find ./functions -type f -exec sh -c 'zip -j -X -q "$2"/$(basename "$1").zip "$1"' sh {} "$workdir" \;

  local lambda_bucket && lambda_bucket=$(get_lambda_bucket_name)
  for zip in "$workdir"/*; do
    aws s3 cp "$zip" "s3://$lambda_bucket/$(basename "$zip")" --profile personal
  done

  rm -rf "$workdir"
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

  if ! [ -x "$(command -v yq)" ]; then
    echo 'exiting early: yq not installed'
    exit
  fi

  deploy_stack
  upload_lambda_function_zips
}

main
