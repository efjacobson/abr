#! /bin/bash

json_config=

region='us-east-1'
stack_name=abr
default_aws_arguments="--region $region --profile personal"

set_config() {
  local describe_stacks_outputs && describe_stacks_outputs=$(eval "aws cloudformation describe-stacks $default_aws_arguments \
    --stack-name $stack_name \
    --query \"Stacks[0].Outputs\"")

  json_config='{'
  while read -r OutputKey; do
    read -r OutputValue
    json_config+="\"$OutputKey\":\"$OutputValue\","
  done < <(echo "$describe_stacks_outputs" | jq -cr '.[] | (.OutputKey, .OutputValue)')
  json_config=${json_config%?}
  json_config+='}'
}

init_config() {
  if [ '' == "$json_config" ]; then
    set_config
  fi
}

get_bucket_name() {
  local bucket_type="$1"
  init_config
  echo "$json_config" | jq -r ".${bucket_type}BucketRef"
}

get_function_arn() {
  local function_name="$1"
  init_config
  local function_arn && function_arn=$(echo "$json_config" | jq -r ".${function_name}Arn")
  if [ 'null' == "$function_arn" ]; then
    echo ''
  else
    echo "$function_arn"
  fi
}
