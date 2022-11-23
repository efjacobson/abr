#! /bin/bash

default_aws_arguments=
region=
profile=
dry_run=true
here="$(dirname "$(realpath "$0")")"
stack_name=abr
template="$here/infra.yaml"

display_help() {
  echo "
Available options:
  --dry-run     When true, no changes are actually made
  --stack-name  Defaults to '$stack_name'
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
  --stack-name=*)
    stack_name="${opt#*=}"
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

create_deploy_template() {
  # echo "$template"
  # return
  # local optional_output_regex='^DefaultBucketOnOriginRequestFunction(Version)?$'

  local AWSCloudFrontCloudFrontOriginAccessIdentity_output_GetAtt_fields=('Id' 'S3CanonicalUserId')
  local AWSCloudFrontDistribution_output_GetAtt_fields=('DomainName' 'Id')
  local AWSIAMRole_output_GetAtt_fields=('Arn' 'RoleId')
  local AWSLambdaFunction_output_GetAtt_fields=('Arn')
  local AWSLambdaVersion_output_GetAtt_fields=('Version')
  local AWSLogsLogGroup_output_GetAtt_fields=('Arn')
  local AWSS3Bucket_output_GetAtt_fields=('Arn' 'DomainName' 'DualStackDomainName' 'RegionalDomainName' 'WebsiteURL')
  local AWSServerlessFunction_output_GetAtt_fields=('Arn')
  local AWSCloudFrontOriginAccessControl_output_GetAtt_fields=('Id')

  local temp_file_0 && temp_file_0="$(mktemp)"
  echo '{}' >"$temp_file_0"
  local outputs && outputs=$(echo '{}' | jq)
  yq '.Resources | keys[]' "$template" | while read -r resource; do
    local raw_resource && raw_resource=$(echo "$resource" | tr -d '"')
    local Ref_filter=". + {\"${raw_resource}Ref\": {\"Value\": \"!Ref $raw_resource\""
    local condition && condition="$(yq ".Resources.$raw_resource.Condition" "$template")"
    if [ 'null' != "$condition" ]; then
      Ref_filter+=",\"Condition\":$condition"
    fi
    # if [[ "$raw_resource" =~ $optional_output_regex ]]; then
    #   Ref_filter+=",\"Condition\":\"CurrentAndIncomingAreDifferent\""
    # fi
    Ref_filter+='}}'
    outputs=$(echo "$outputs" | jq "$Ref_filter")

    local filter=".Resources.$raw_resource.Type"
    local type && type=$(yq -r "$filter" "$template")
    local config=${type//:/}
    local output_fields="$config"_output_GetAtt_fields[@]
    local count=0
    for GetAtt_field in ${!output_fields}; do
      GetAtt_filter=". + {\"$raw_resource$GetAtt_field\": {\"Value\": \"!GetAtt $raw_resource.$GetAtt_field\""
      if [ 'null' != "$condition" ]; then
        GetAtt_filter+=",\"Condition\":$condition"
      fi
      # if [[ "$raw_resource" =~ $optional_output_regex ]]; then
      #   GetAtt_filter+=",\"Condition\":\"CurrentAndIncomingAreDifferent\""
      # fi
      GetAtt_filter+='}}'
      outputs=$(echo "$outputs" | jq "$GetAtt_filter")
      count=$((count + 1))
    done
    if [ "$count" == 0 ] && [ 'AWSS3BucketPolicy' != "$config" ] && [ 'AWSLambdaPermission' != "$config" ]; then
      echo "no config for $config!"
    fi
    local insert_filter=". + {\"Outputs\":$outputs}"
    local result && result=$(cat "$temp_file_0" | yq "$insert_filter")
    echo "$result" >"$temp_file_0"
  done
  local final_outputs && final_outputs=$(cat "$temp_file_0" | yq -y | sed -E 's/(Value: '\'')/Value: /g' | sed -E 's/^(.+)Value(.+)('\'')$/\1Value\2/g')
  echo "$final_outputs" >"$temp_file_0"
  local deploy_template && deploy_template=$(mktemp)
  cp "$template" "$deploy_template"
  echo "" >>"$deploy_template"
  local temp_file_0 && temp_file_1="$(mktemp)"
  cat "$deploy_template" "$temp_file_0" >"$temp_file_1"
  cp "$temp_file_1" "$deploy_template"
  rm "$temp_file_1" "$temp_file_0"
  echo "$deploy_template"
}

deploy_stack() {
  local parameter_overrides=("$@")
  local deploy_template && deploy_template=$(create_deploy_template "${parameter_overrides[@]}")

  parameter_overrides+=("DefaultBucketOnCreateObjectFunctionArn=$(get_function_arn 'DefaultBucketOnCreateObjectFunction')")
  parameter_overrides_option="--parameter-overrides ${parameter_overrides[*]}"

  local deploy_command="aws cloudformation deploy \
    --template-file $deploy_template  \
    --stack-name $stack_name \
    --capabilities CAPABILITY_IAM \
    $parameter_overrides_option \
    $default_aws_arguments"

  if $dry_run; then
    deploy_command+=' --no-execute-changeset'
  fi

  echo 'deploying...'
  local deploy_output && deploy_output=$(eval "$deploy_command")
  rm "$deploy_template"
  local label="$deploy_command"
  if $dry_run; then
    label="[dry run] $label"
  fi
  echo "$deploy_output"

  local ultimate_line && ultimate_line=$(echo "$deploy_output" | tail -n1)
  local regex='^aws cloudformation describe-change-set'
  if [[ ! "$ultimate_line" =~ $regex ]]; then
    return
  fi

  if $dry_run; then
    local describe_command="$ultimate_line $default_aws_arguments"
    local describe_output && describe_output=$(eval "$describe_command")
    label=describe_command
    if $dry_run; then
      label="[dry run] $label"
    fi
    echo "$describe_output"
    return
  fi

  set_config
}

get_latest_version() {
  local function="$1"
  local latest
  for version in "$here/lambda-functions/$function"/*; do
    latest=${version##*/}
  done
  if [ '*' == "$latest" ]; then
    echo "no versions for function: $function. exiting early..."
    exit
  fi
  echo "$latest"
}

upload_lambda_functions() {
  for function in "$here/lambda-functions"/*; do
    if [ -d "$function/latest" ]; then
      rm -rf "$function/latest"
    fi
  done

  bucket="$(get_bucket_name 'LambdaFunction')"
  while IFS= read -r filepath; do
    base_name="$(basename "$filepath")"
    dir_name="$(dirname "$(realpath "$filepath")")"
    dir_names_dir_name=$(dirname "$dir_name")

    function_name=${dir_names_dir_name##*/}
    version=${dir_name##*/}
    key="$function_name/$version/$base_name.zip"

    zip_path="$filepath.zip"
    zip -j -X -q "$zip_path" "$filepath"
    checksum="$(openssl dgst -sha256 -binary "$zip_path" | openssl enc -base64)"

    aws s3api put-object \
      --bucket "$bucket" \
      --key "$key" \
      --body "$zip_path" \
      --checksum-sha256 "$checksum" \
      --profile personal >>/dev/null
    echo "uploaded $key to s3://$bucket/$key with sha256 checksum $checksum"
    rm -f "$zip_path"
  done < <(find "$here/lambda-functions/." -name '*.js')

  for function in "$here/lambda-functions"/*; do
    cp -r "$function/$(get_latest_version "${function##*/}")" "$function/latest"
  done
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

  # shellcheck source=/dev/null
  source "$here/shared.bash" "$stack_name"

  latestOnOrigin=$(get_latest_version default-bucket-on-origin-request)
  if [ '' == "$latestOnOrigin" ]; then
    echo 'gotta make some functions bro'
    exit
  fi
  SemanticVersionFromFile="$latestOnOrigin"
  FriendlySemanticVersionFromFile="${latestOnOrigin//./-}"

  if [ -f "$here/.create" ]; then
    # todo: get status, wait til done, etc
    cat "$here/.create"
    rm -f "$here/.create"
    exit
  fi

  local drift_detection_status
  if [ ! -f "$here/.drift" ]; then
    eval "aws cloudformation detect-stack-drift \
      --stack-name $stack_name \
      --query=\"StackDriftDetectionId\" \
      --output=text \
      $default_aws_arguments" >>"$here/.drift" 2>&1

    if [[ $(cat "$here/.drift") =~ 'error' ]]; then
      rm -f "$here/.drift"
      local template_path && template_path=$(create_deploy_template)

      echo 'creating stack...'
      eval "aws cloudformation create-stack \
        --stack-name $stack_name \
        --template-body file://$template_path \
        --region $region \
        --profile $profile \
        --capabilities CAPABILITY_IAM \
        --enable-termination-protection \
        --parameters ParameterKey=IsCreate,ParameterValue=true ParameterKey=DefaultBucketOnOriginRequestFunctionFromFileName,ParameterValue=$stack_name-DefaultBucketOnOriginRequestFunction_$FriendlySemanticVersionFromFile-file ParameterKey=DefaultBucketOnOriginRequestFunctionFromAssociationName,ParameterValue=$stack_name-DefaultBucketOnOriginRequestFunction_$FriendlySemanticVersionFromFile-association  ParameterKey=DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion,ParameterValue=$SemanticVersionFromFile ParameterKey=DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion,ParameterValue=$SemanticVersionFromFile" >>"$here/.create" 2>&1

      if [[ $(cat "$here/.create") =~ 'error' ]]; then
        cat "$here/.create"
        rm -f "$here/.create"
        exit
      fi
      main
      exit
    fi

    sleep 3
    main && exit
  else
    drift_detection_status=$(eval "aws cloudformation describe-stack-drift-detection-status \
      --stack-drift-detection-id $(cat "$here/.drift") \
      $default_aws_arguments")

    if [ 'DETECTION_COMPLETE' != "$(echo "$drift_detection_status" | jq -r '.DetectionStatus')" ]; then
      echo 'still detecting drift, sleeping for 3 seconds...'
      sleep 3
      main && exit
    fi
    drift_detection_status="$(echo "$drift_detection_status" | jq -r '.StackDriftStatus')"
    if [ 'IN_SYNC' == "$drift_detection_status" ]; then
      echo 'stack is in sync...'
      rm -f "$here/.drift"
    else
      while true; do
        read -r -p "stack is not in sync, has status [$drift_detection_status]. continue deploying? (y/N): " answer
        case "$answer" in
        Y | y)
          rm -f "$here/.drift"
          break
          ;;
        *)
          exit
          ;;
        esac
      done
    fi
  fi

  local parameter_overrides=()
  latest_default_bucket_on_create_object=$(get_latest_version default-bucket-on-create-object)
  if [ '' != "$latest_default_bucket_on_create_object" ]; then
    parameter_overrides+=("DefaultBucketOnCreateObjectFunctionSemanticVersion=$latest_default_bucket_on_create_object")
  fi

  latest_default_bucket_on_origin_request=$(get_latest_version default-bucket-on-origin-request)
  SemanticVersionFromFile="$latest_default_bucket_on_origin_request"
  FriendlySemanticVersionFromFile="${latest_default_bucket_on_origin_request//./-}"
  # fixme: could do a list of major, minor, patch, source

  local distribution_id && distribution_id=$(get_distribution_id 'Primary')
  if [ '' == "$distribution_id" ]; then
    echo 'do_deploy [file,fileCloneAsDistro]:distro'
    echo 'deploy again.'
    exit
  fi

  if [ '0' != "$quantity" ]; then
    DistroAssociation=$(echo "$primary_distribution_lambda_function_associations" | jq '.Items[] | select(.EventType=="origin-request")')
    if [ '' != "$DistroAssociation" ]; then
      DistroFunctionArn=$(echo "$origin_request_lambda_association" | jq -r '.LambdaFunctionARN')
      DistroFunctionVersion="${DistroFunctionArn##*_}"
      DistroFunctionVersion=$(echo "$DistroFunctionVersion" | sed -E 's/:[0-9]+$//') # removes aws lambda version
      suffix='-association'
      DistroFunctionVersion="${DistroFunctionVersion/$suffix/}"
      DistroFunctionVersion="${DistroFunctionVersion//-/.}"
      if [ "$SemanticVersionFromFile" != "$DistroFunctionVersion" ]; then
        aws lambda get-function --function-name "$stack_name-DefaultBucketOnOriginRequestFunction_$FriendlySemanticVersionFromFile-file" --region us-east-1 --profile personal
        echo "if function exists, use it for association. if not, use what is already on the distro but create this new function"
        functionFromFileExists=false
        if $functionFromFileExists; then
          echo 'do_deploy [file,distro]:file'
          echo 'deploy again?'
          exit
        else
          echo 'do_deploy [file,distro]:distro'
          echo 'deploy again.'
        fi
      fi
      exit
    fi
  fi

  if [ '' == "$distribution_id" ]; then
    echo 'do_deploy [file,fileCloneAsDistro]:distro'
    echo 'deploy again.'
    exit
  fi

  echo "nice maybe"
  exit

  primary_distribution_lambda_function_associations=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile personal --query="DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations")
  quantity=$(echo "$primary_distribution_lambda_function_associations" | jq '.Quantity')
  if [ '0' == "$quantity" ]; then
    echo 'do_deploy [SemanticVersionFromFile][0]'
    exit
  fi

  origin_request_lambda_association=$(echo "$primary_distribution_lambda_function_associations" | jq '.Items[] | select(.EventType=="origin-request")')
  if [ '' == "$origin_request_lambda_association" ]; then
    echo 'do_deploy [SemanticVersionFromFile][0]'
    exit
  fi

  # [v2,v1]
  # INVALID - v1-0 not ready to be deleted yet, refuse to deploy

  origin_request_lambda_function_arn=$(echo "$origin_request_lambda_association" | jq -r '.LambdaFunctionARN')
  version="${origin_request_lambda_function_arn##*_}"
  echo "this is probabliy the wrong versin: $version since it has the index"
  version=$(echo "$version" | sed -E 's/:[0-9]+$//')
  version="${version//-/.}"
  SemanticVersionFromDistro="$version"
  if [ "$SemanticVersionFromDistro" == "$SemanticVersionFromFile" ]; then
    echo 'do_deploy [SemanticVersionFromFile,SemanticVersionFromDistro][0]'
    exit
  fi

  exit

  # 0 decided by file structure
  # 1 decided by distro description

  # always create both

  # {fileV,distroV:!null&!fileV}
  # if fileV exists, use it
  # if not, use distroV

  # {fileV,distroV:null}
  # use fileV, create distroV as fileV clone

  # {fileV,distroV:fileV}
  # use distroV

  # {file:v1,distro:null} => [file,distroButReallyFile], associateAt:distroButReallyFile, createAtIndex0:true, createAtIndex1:true
  # v1-file: no choice. make both

  # {file:v1,distro:v1} => [file,distro], associateAt:distro, createAtIndex0:true, createAtIndex1:true
  # v1-distro: same version. make both

  # {file:v2,distro:v1} => [file,distro], associateAt:disstro
  # v1-distro: different. use one that already exists and make both

  # [v2, v2]
  # v2-1: same. do not make v2-0

  # 0 decided by file structure
  # 1 decided by distro description

  # [v1]
  # v1-0: no choice

  # [v2,v1]
  # INVALID - v1-0 not ready to be deleted yet, refuse to deploy

  # [v1,v1]
  # v1-0: same but 0 exists so use that

  # [v1,v1]
  # v1-1: same, both exist so use one from distro

  # ...repeat infinitely

  # [v2,v1]
  # v1-1: different but 1 exists so use that

  # [v2,v1]
  # v2-1: different, both exist so use 0 (file)

  # [v2,v2]
  # v2-1: same, both exist so use one from distro

  # ...repeat infinitely

  if [ '' != "$latest_default_bucket_on_origin_request" ]; then
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionSemanticVersion=$latest_default_bucket_on_origin_request")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFriendlySemanticVersion=${latest_default_bucket_on_origin_request//./-}")
  fi

  fn_name="$stack_name-DefaultBucketOnOriginRequestFunction_${latest_default_bucket_on_origin_request//./-}"
  incoming_default_bucket_on_origin_request_function_name="$fn_name"
  incoming_default_bucket_on_origin_request_function_semantic_version="$latest_default_bucket_on_origin_request"
  functions="$incoming_default_bucket_on_origin_request_function_name:$incoming_default_bucket_on_origin_request_function_semantic_version"
  associate_function=0

  local distribution_id && distribution_id=$(get_distribution_id 'Primary')
  primary_distribution_lambda_function_associations=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile personal --query="DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations")
  quantity=$(echo "$primary_distribution_lambda_function_associations" | jq '.Quantity')
  if [ '0' != "$quantity" ]; then
    origin_request_lambda_association=$(echo "$primary_distribution_lambda_function_associations" | jq '.Items[] | select(.EventType=="origin-request")')
    if [ '' != "$origin_request_lambda_association" ]; then
      origin_request_lambda_function_arn=$(echo "$origin_request_lambda_association" | jq -r '.LambdaFunctionARN')
      prefix='arn:aws:lambda:us-east-1:458362456643:function:'
      origin_request_lambda_function_name="${origin_request_lambda_function_arn/$prefix/}"
      origin_request_lambda_function_name="$(echo "$origin_request_lambda_function_name" | sed -E 's/:[0-9]+$//')"
      parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationName=$origin_request_lambda_function_name")
      version="${origin_request_lambda_function_arn##*_}"
      version=$(echo "$version" | sed -E 's/:[0-9]+$//')
      version="${version//-/.}"
      parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion=$version")
      functions+="$origin_request_lambda_function_name:$version"
    fi
  fi

  parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileName=$incoming_default_bucket_on_origin_request_function_name")
  parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion=$incoming_default_bucket_on_origin_request_function_semantic_version")

  if [ '' == "$(aws s3api head-bucket --bucket 458362456643-"$stack_name"-lambda-functions --profile personal 2>&1 >/dev/null)" ]; then
    upload_lambda_functions
    deploy_stack "${parameter_overrides[@]}"
  else
    deploy_stack "${parameter_overrides[@]}"
    upload_lambda_functions
  fi
}

main
