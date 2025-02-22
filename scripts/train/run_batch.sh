#!/bin/bash -e
# Copyright 2022 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export CLUSTER_PREFIX=$1
export NODE_COUNT=$2
export MODEL_CHECKPOINT=$3
export DATA=$4
export MODEL_OUTPUT=$5
export ZONE=$6
export PROJECT=$7
export MACHINE_TYPE=$8
export GPU_TYPE=$9
export GPU_COUNT=${10}
export BATCH_SIZE=${11}
export EPOCHS=${12}
export ID=${13}
export IMAGE_TAG=${14}
export JOB_ID=${CLUSTER_PREFIX}-${ID}
shopt -s extglob
export REGION=${ZONE/%-+([a-z0-9])/}

export GCS_PATH=${MODEL_OUTPUT/\/gcs\//gs:\/\/}/deployment
export JOB_FOUND=$(gsutil ls $GCS_PATH)

if [[ -n "${JOB_FOUND}" ]]; then
  echo "Skipping further retries..."
  exit 1
fi
echo seed > deployment.txt
gsutil cp deployment.txt $GCS_PATH/deployment.txt

export SERVICE_ACCOUNT=$(gcloud config get account)
export OS_LOGIN_USER=$(gcloud iam service-accounts describe ${SERVICE_ACCOUNT} | grep uniqueId | sed -e "s/.* '\(.*\)'/sa_\1/")

echo User is ${OS_LOGIN_USER}

export TRAIN_CMD="./train.sh ${MODEL_CHECKPOINT} ${DATA} ${MODEL_OUTPUT} ${ZONE} ${BATCH_SIZE} ${EPOCHS} ${GPU_COUNT}"
export START="docker pull gcr.io/llm-containers/train:${IMAGE_TAG}; nvidia-persistenced; docker run --ipc host --network host --hostname \$(hostname) --gpus all -v /etc/ssh:/etc/ssh gcr.io/llm-containers/train:${IMAGE_TAG} ${TRAIN_CMD}"
#gcloud compute resource-policies create group-placement ${JOB_ID}  --collocation COLLOCATED  --region ${REGION}  --project ${PROJECT}
#gcloud compute instance-templates create ${JOB_ID} --project=${PROJECT} --machine-type=${MACHINE_TYPE} --network-interface=network-tier=PREMIUM,network=default,address= --metadata=install-unattended-upgrades=false,enable-oslogin=TRUE,jupyter-user=${OS_LOGIN_USER},install-nvidia-driver=True,startup-script="${START}" --maintenance-policy=TERMINATE --provisioning-model=STANDARD --scopes=https://www.googleapis.com/auth/cloud-platform --accelerator=count=${GPU_COUNT},type=${GPU_TYPE} --create-disk=auto-delete=yes,boot=yes,device-name=gpu1,image=projects/ml-images/global/images/c2-deeplearning-pytorch-1-11-cu113-v20220701-debian-10,mode=rw,size=2000,type=pd-ssd --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any --resource-policies=${JOB_ID} --no-restart-on-failure
#gcloud compute instance-groups managed create ${JOB_ID} --project=${PROJECT} --base-instance-name=${JOB_ID} --size=${NODE_COUNT} --template=${JOB_ID} --zone=${ZONE} --list-managed-instances-results=PAGELESS

export ACTION=CREATE
export NAME_PREFIX=${JOB_ID}
export INSTANCE_COUNT=${NODE_COUNT}
export VM_TYPE=${MACHINE_TYPE}
export ACCELERATOR_TYPE=${GPU_TYPE}
export IMAGE_NAME=c0-deeplearning-common-cu113-v20221026-debian-10
export GCS_PATH=${MODEL_OUTPUT/\/gcs\//gs:\/\/}/deployment
export METADATA="{install-unattended-upgrades=\"false\",enable-oslogin=\"TRUE\",jupyter-user=\"${OS_LOGIN_USER}\",install-nvidia-driver=\"True\"}"
export STARTUP_SCRIPT=${START}
export PROJECT_ID=${PROJECT}
export SHOW_PROXY_URL=no
export LABELS="{gcpllm=\"$CLUSTER_PREFIX\"}"
#export DISK_SIZE_GB=1000
/usr/entrypoint.sh

echo "Provishioning cluster..."

(sleep 2400;echo check > check.txt) &


export EXIT_CODE=
export LOG_START_TIME=$(date -Ins | sed -e "s/,/\./")
while [[ -z "$EXIT_CODE" ]]; do
  export RESULT=$(gsutil cat ${MODEL_OUTPUT/\/gcs\//gs:\/\/}/progress.txt 2> /dev/null)
  if [[ "${RESULT}" == "succeeded" ]]; then
    echo "Training finished successfully!"
    export EXIT_CODE=0
    break
  fi
  if [[ "${RESULT}" == "failed" ]]; then
    echo "Training failed!"
    export EXIT_CODE=1
    break
  fi

  if [[ -e check.txt ]]; then
    rm check.txt
    
    if [[ "${RESULT}" != "started" ]]; then
      echo "Timeout! Training not started in 20 minutes"
      export EXIT_CODE=2
      break
    fi
  fi
  export LOG_END_TIME=$(date -Ins | sed -e "s/,/\./")
  sleep 15
  # Reading logs 15 seconds behind to give them a chance to be collected.
  gcloud logging read "log_name=projects/${PROJECT}/logs/deepspeed labels.\"compute.googleapis.com/resource_name\"=~\"${JOB_ID}\" timestamp>=\"${LOG_START_TIME}\" timestamp<\"${LOG_END_TIME}\"" --project=${PROJECT} | yq -r .textPayload | tac
  export LOG_START_TIME=${LOG_END_TIME}
  
done

# Only delete cluster when training succeeds. Otherwise, keep the cluster for investigation
if [[ "${EXIT_CODE}" == "0" ]]; then
  #gcloud compute instance-groups managed delete ${JOB_ID} --quiet --project=${PROJECT} --zone=${ZONE}
  #gcloud compute instance-templates delete ${JOB_ID} --quiet --project=${PROJECT}
  export ACTION=DESTROY
  /usr/entrypoint.sh
fi

exit $EXIT_CODE