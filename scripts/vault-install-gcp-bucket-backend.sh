#!/bin/bash
#Author: Alex


mkdir -p ~/gcp-vault
cd ~/gcp-vault

### pass ENVIRONMENT VARIABLES

BUCKET_NAME=kubelancer-vault-data-bucket-demo
KEYRINGS=kubelancer-testring-demo
KEYS=kubelancer-testkey-demo
SA=vault-svc-account-demo

### export ENVIRONMENT VARIABLES

export PROJECT_ID=your-gcp-project-name
export PROJECT_NUMBER=`gcloud projects describe $PROJECT_ID --format="value(projectNumber)"`
export VAULT_SERVICE_ACCOUNT=$SA@$PROJECT_ID.iam.gserviceaccount.com

### Create Service Account

gcloud iam service-accounts create $SA --display-name "Vault Service Account"
gcloud iam service-accounts keys create vault-svc.json --iam-account=$VAULT_SERVICE_ACCOUNT

### Enable cloudkms API
gcloud services enable cloudkms.googleapis.com
###Update Roles for Service Account
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/iam.serviceAccountAdmin
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/iam.serviceAccountKeyAdmin
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/compute.viewer
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/storage.admingcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/storage.objectViewer
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/cloudkms.admin
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/cloudkms.cryptoKeyEncrypterDecrypter
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/owner
echo " "
echo "------------------------------"
echo "Updating policy, Please wait ......."
sleep 30
echo "------------------------------"
## To list roles

gcloud projects get-iam-policy $PROJECT_ID  \
--flatten="bindings[].members" \
--format='table(bindings.role)' \
--filter="bindings.members:$VAULT_SERVICE_ACCOUNT"


## Create Cluster
gcloud container  clusters create cluster-1 --machine-type "n1-standard-1" --zone us-central1-a  --num-nodes 2 --enable-ip-alias
sleep 30
gcloud container clusters get-credentials cluster-1 --zone us-central1-a
kubectl get nodes

### Google Cloud Storage Storage Backend

gsutil mb gs://$BUCKET_NAME
gsutil acl ch -r -u AllUsers:R gs://$BUCKET_NAME
gsutil acl ch  -u AllUsers:R gs://$BUCKET_NAME

### Creating symmetric keys

gcloud kms keyrings create $KEYRINGS   --location global
gcloud kms keys create $KEYS \
  --location global \
  --keyring $KEYRINGS \
  --purpose encryption \
--rotation-period  365d \
--next-rotation-time 2021-01-01

gcloud kms keys add-iam-policy-binding $KEYS \
    --location global \
    --keyring $KEYRINGS \
    --member serviceAccount:$VAULT_SERVICE_ACCOUNT \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter

## Install vault
## Note: use helm verion 3

kubectl create secret generic google-secret --from-literal=GOOGLE_APPLICATION_CREDENTIALS=/etc/gcp/service-account.json --from-file=service-account.json=./vault-svc.json


git clone https://github.com/banzaicloud/bank-vaults.git
cd ~/gcp-vault/bank-vaults/charts

helm  install vault \
--set "vault.customSecrets[0].secretName=google-secret" \
--set "vault.customSecrets[0].mountPath=/etc/gcp" \
--set "vault.config.storage.gcs.bucket=$BUCKET_NAME" \
--set "vault.config.seal.gcpckms.project=$PROJECT_ID" \
--set "vault.config.seal.gcpckms.region=global" \
--set "vault.config.seal.gcpckms.key_ring=$KEYRINGS" \
--set "vault.config.seal.gcpckms.crypto_key=$KEYS" \
--set "unsealer.args[0]=--mode" \
--set "unsealer.args[1]=google-cloud-kms-gcs" \
--set "unsealer.args[2]=--google-cloud-kms-key-ring" \
--set "unsealer.args[3]=$KEYRINGS" \
--set "unsealer.args[4]=--google-cloud-kms-crypto-key" \
--set "unsealer.args[5]=$KEYS" \
--set "unsealer.args[6]=--google-cloud-kms-location" \
--set "unsealer.args[7]=global" \
--set "unsealer.args[8]=--google-cloud-kms-project" \
--set "unsealer.args[9]=$PROJECT_ID" \
--set "unsealer.args[10]=--google-cloud-storage-bucket" \
--set "unsealer.args[11]=$BUCKET_NAME" \
--set "service.type=LoadBalancer" \
--name-template vault

### Decrypt Vault Token
cd ~/gcp-vault
echo "------------------------------"
echo "Installation is in progress, Please wait ..............."
sleep 60
echo "------------------------------"
echo "Decrypting VAULT_TOKEN"
gsutil copy gs://$BUCKET_NAME/vault-root .
gcloud kms decrypt --key=$KEYS --keyring=$KEYRINGS --location=global --ciphertext-file=vault-root --plaintext-file=vault-root.dec
## Root Token
for i in `cat vault-root.dec`; do export VAULT_TOKEN=$i; done

### Installing Vault-Client
echo "------------------------------"
echo "Installing Vault Client"
echo "------------------------------"
cd ~/gcp-vault
https://releases.hashicorp.com/vault/1.4.0/vault_1.4.0_linux_amd64.zip
unzip vault_1.4.0_linux_amd64.zip
sudo cp -rf vault /usr/local/bin/ ; sudo chmod +x /us

## Vault login
echo "------------------------------"
echo "LoadBalancer provision is in progress, Please wait ..............."
sleep 60
echo "------------------------------"
export SERVICE_IP=$(kubectl get svc --namespace default vault -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "VAULT_ADDR"
export VAULT_ADDR=https://$SERVICE_IP:8200
echo "TLS SKIP"
export VAULT_SKIP_VERIFY=1
echo "Vault status"
vault status
echo "Vault Login"
vault login -method=token token=$VAULT_TOKEN
echo "------------------------------"
echo "Setup Complete, Have a great day"
