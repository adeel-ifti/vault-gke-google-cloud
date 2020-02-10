# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


### Google Cloud Storage Storage Backend
gsutil mb gs://kubelancer-vault-data-bucket
### Creating symmetric keys
gcloud kms keyrings create kubelancer-testring   --location global
gcloud kms keys create kubelancer-testkey \
  --location global \
  --keyring kubelancer-testring \
  --purpose encryption \
--rotation-period  365d \
--next-rotation-time 2021-01-01
​
### Install Vault
mkdir -p ~/Alex/vault-testing
cd ~/Alex/vault-testing
git clone https://github.com/banzaicloud/bank-vaults.git
cd bank-vaults/charts/

kubectl create secret generic google 
--from-literal=GOOGLE_APPLICATION_CREDENTIALS=/etc/gcp/service-account.json 
--from-file=service-account.json=./service-account.json

helm install vault \
--set "vault.customSecrets[0].secretName=google" \
--set "vault.customSecrets[0].mountPath=/etc/gcp" \
--set "vault.config.storage.gcs.bucket=kubelancer-vault-data-bucket" \
--set "vault.config.seal.gcpckms.project=prefab-surfer-263006" \
--set "vault.config.seal.gcpckms.region=global" \
--set "vault.config.seal.gcpckms.key_ring=kubelancer-testring" \
--set "vault.config.seal.gcpckms.crypto_key=kubelancer-testkey" \
--set "unsealer.args[0]=--mode" \
--set "unsealer.args[1]=google-cloud-kms-gcs" \
--set "unsealer.args[2]=--google-cloud-kms-key-ring" \
--set "unsealer.args[3]=kubelancer-testring" \
--set "unsealer.args[4]=--google-cloud-kms-crypto-key" \
--set "unsealer.args[5]=kubelancer-testkey" \
--set "unsealer.args[6]=--google-cloud-kms-location" \
--set "unsealer.args[7]=global" \
--set "unsealer.args[8]=--google-cloud-kms-project" \
--set "unsealer.args[9]=prefab-surfer-263006" \
--set "unsealer.args[10]=--google-cloud-storage-bucket" \
--set "unsealer.args[11]=kubelancer-vault-data-bucket" \
--name vault
​
### Decrypt Vault Token
cd ~/Alex/vault-testing
gsutil copy gs://kubelancer-vault-data-bucket/vault-root .
gcloud kms decrypt \
    	--key=kubelancer-testkey \
    	--keyring=kubelancer-testring \
    	--location=global \
    	--ciphertext-file=vault-root \
    	--plaintext-file=vault-root.dec
cat vault-root.dec