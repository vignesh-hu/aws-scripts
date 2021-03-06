#!/usr/bin/env bash

account_aliases=
account_id=

declare -A target_buckets

function create_log_buckets() {
  for reg in "${!target_buckets[@]}"
  do
    if aws s3 ls "s3://s3-bucket-logging-${account_id}-${reg}" 2>&1 | grep -q 'An error occurred'
    then
      if [[ "${reg}" == "us-east-1" ]];
      then
        aws s3api create-bucket \
        --bucket "s3-bucket-logging-${account_id}-${reg}" \
        --region "${reg}" \
        --grant-read-acp uri=http://acs.amazonaws.com/groups/s3/LogDelivery \
        --grant-write uri=http://acs.amazonaws.com/groups/s3/LogDelivery
      else
        aws s3api create-bucket \
        --bucket "s3-bucket-logging-${account_id}-${reg}" \
        --region "${reg}" \
        --create-bucket-configuration "LocationConstraint=${reg}" \
        --grant-read-acp uri=http://acs.amazonaws.com/groups/s3/LogDelivery \
        --grant-write uri=http://acs.amazonaws.com/groups/s3/LogDelivery
      fi

      sleep 5
      aws s3api put-bucket-lifecycle-configuration --bucket "s3-bucket-logging-${account_id}-${reg}" --lifecycle-configuration file://s3_lifecycle_policy.json
    else
      echo "Bucket 's3-bucket-logging-${account_id}-${reg}' already exists in the current AWS account. Enabling logging..."
    fi
  done
}

function activate_logging() {
  buckets=( $(aws s3 ls | awk '{print $3}') )

  for bucket in ${buckets[@]}
  do
    echo "---"
    bucket_region=$(aws s3api get-bucket-location --bucket ${bucket} --query 'LocationConstraint' --output text)

    if [[ "${bucket_region}" == "None" ]];
    then
      bucket_region="us-east-1"
    elif [[ "${bucket_region}" == "EU" ]];
    then
      bucket_region="eu-west-1"
    fi

    echo "Enabling logging for ${bucket}, sending logs to ${target_buckets[${bucket_region}]}."
    aws s3api put-bucket-logging --bucket "${bucket}" --bucket-logging-status '{"LoggingEnabled": {"TargetBucket": "'${target_buckets[${bucket_region}]}'","TargetPrefix": "'${bucket}'/"}}'
  done
}

function main() {
  # for profile in $(aws-okta list | awk '{print $1}' | grep -E "okta.*prod")
  # do
  #   echo "---"
  #   echo "${profile}"
  # done

  account_aliases=$(aws iam list-account-aliases --query 'AccountAliases' --output text);
  account_id=$(aws sts get-caller-identity --query 'Account' --output text);

  [[ -z "${account_id}" ]] && ( echo "No credentials available to use!" ; exit 5 );

  target_buckets=(
    ["eu-west-1"]="s3-bucket-logging-${account_id}-eu-west-1"
    ["eu-west-2"]="s3-bucket-logging-${account_id}-eu-west-2"
    ["us-east-1"]="s3-bucket-logging-${account_id}-us-east-1"
  )

  echo -e "Running in account with alias: ${account_aliases} id: ${account_id}"

  echo "-----------------"
  echo -e "Creating logging buckets..."
  create_log_buckets

  echo "-----------------"
  echo -e "Enabling S3 bucket logging in account: ${account_id}..."
  activate_logging
}

main
