#! /bin/bash

dry_run=true
stack_name=abr
region=us-east-1

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
  default_arguments="--region $region --profile personal"

  deploy_command="aws cloudformation deploy --template-file ./infra.yaml --stack-name $stack_name $default_arguments"
  if $dry_run; then
    deploy_command+=' --no-execute-changeset'
  fi

  deploy_output=$(eval "$deploy_command")
  echo "$deploy_output"
  ultimate_line=$(echo "$deploy_output" | tail -n1)
  if [ "No changes to deploy. Stack $stack_name is up to date" == "$ultimate_line" ]; then
    return
  fi

  if $dry_run; then
    deploy_command="$ultimate_line $default_arguments"
    printf '\n%s\n\n' 'dry run, change set description:'
    eval "$deploy_command"
    return
  fi

  outputs=$(eval "aws cloudformation describe-stacks $default_arguments \
    --stack-name $stack_name \
    --query \"Stacks[0].Outputs\"")

  config='{'
  while read -r OutputKey; do
    read -r OutputValue
    config+="\"$OutputKey\":\"$OutputValue\","
  done < <(echo "$outputs" | jq -cr '.[] | (.OutputKey, .OutputValue)')
  config=${config%?}
  config+='}'

  echo $config | jq '.' | yq -y >"./.$stack_name-stack-outputs.yaml"
}

deploy_lambda_functions() {
  find ./functions -type f -exec zip -j -X -q '{}'.zip '{}' \;
  # do the thing...
  find ./functions -name '*.zip' -exec rm '{}' \;
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
  deploy_lambda_functions
}

main
