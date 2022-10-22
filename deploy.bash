#! /bin/bash

dry_run=true

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --no-execute-changeset flag
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

main() {
  if [ "$dry_run" == false ]; then
    aws cloudformation deploy \
      --profile personal \
      --region=us-east-1 \
      --template-file ./infra.yaml \
      --stack-name abr
  else
    aws cloudformation deploy \
      --profile personal \
      --region=us-east-1 \
      --template-file ./infra.yaml \
      --stack-name abr \
      --no-execute-changeset
  fi
}

main
