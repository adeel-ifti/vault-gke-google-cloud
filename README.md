# GCP, Kubernetes - Installing Hashi Vault with KMS encrypted storage bucket as vault backend

Setting up:
* Make sure gcloud sdk is installed and connected to your gcp account & project. 
* gsutil is installed
* Helm client is installed on your local machine, if not follow instructions at the bottom. 
* Vault client from Hashicorp is installed, if not follow instructions at the bottom .


Create work directory and GCP Storage bucket for vault backend:

```bash
rm -rf ~/github/gcp-vault
mkdir -p ~/github/gcp-vault
cd ~/github/gcp-vault

gsutil mb gs://vault-data-bucket
```

Creating vault svc account with appropriate permissions. Compute role is only needed if you want to fetch vault kv secrets by compute instances. Remove unwanted permissions before running the command. 
```bash
gcloud iam service-accounts create vault-svc-account --display-name "Vault Service Account"
gcloud iam service-accounts keys create vault-svc.json --iam-account=$VAULT_SERVICE_ACCOUNT 

gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/iam.serviceAccountUser
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/iam.serviceAccountKeyUser
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/compute.User
gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$VAULT_SERVICE_ACCOUNT --role=roles/cloudkms.User
```

![gcp iam service accounts](assets/gcp-iam-service-accounts.jpg?raw=true "gcp iam service accounts")


Creating symmetric keys and setting GCP project variables:

```bash
export PROJECT_ID=`gcloud config get-value core/project`
export PROJECT_NUMBER=`gcloud projects describe $PROJECT_ID --format="value(projectNumber)"`
export VAULT_SERVICE_ACCOUNT=vault-svc-account@$PROJECT_ID.iam.gserviceaccount.com

gcloud kms keyrings create vault-backend-testring --location global
```

Create GCP kms key using above keyring:

```bash
gcloud kms keys create vault-backend-testkey \
  --location global \
  --keyring vault-backend-testring \
  --purpose encryption \
  --rotation-period  365d \
  --next-rotation-time 2021-01-01
```


# GCP Kubernetes - Installing Hashi Vault Helm Chart (Banzai provided)

Below is an important step where we mount a secret containing service account credentials json. This will then be passed to Vault helm install command to allow it to access GCP services (KMS, Storage):

```bash
gcloud container clusters create cluster-1 --machine-type "n1-standard-1" --zone us-central1-a  --num-nodes 2 --enable-ip-alias
sleep 30
gcloud container clusters get-credentials cluster-1 --zone us-central1-a
kubectl get nodes

kubectl create secret generic vault-sa-secret --from-literal=GOOGLE_APPLICATION_CREDENTIALS=/etc/gcp/service-account.json --from-file=service-account.json=./vault-svc.json
```
![gke cluster create](assets/gke-cluster-create.jpg?raw=true "gke cluster create")

We are using Banzai Cloud provided chart but same works for official Hashi Vault deployment as well. Banzai has good support on github and has been production tested for couple of years. Install the chart providing with GCP storage bucket and KMS:

```bash
git clone https://github.com/banzaicloud/bank-vaults.git
cd bank-vaults/charts/
```

```bash
helm install vault \
--set "vault.customSecrets[0].secretName=vault-sa-secret" \
--set "vault.customSecrets[0].mountPath=/etc/gcp" \
--set "vault.config.storage.gcs.bucket=vault-data-bucket" \
--set "vault.config.seal.gcpckms.project=prefab-surfer-263006" \
--set "vault.config.seal.gcpckms.region=global" \
--set "vault.config.seal.gcpckms.key_ring=vault-backend-testring" \
--set "vault.config.seal.gcpckms.crypto_key=vault-backend-testkey" \
--set "unsealer.args[0]=--mode" \
--set "unsealer.args[1]=google-cloud-kms-gcs" \
--set "unsealer.args[2]=--google-cloud-kms-key-ring" \
--set "unsealer.args[3]=vault-backend-testring" \
--set "unsealer.args[4]=--google-cloud-kms-crypto-key" \
--set "unsealer.args[5]=vault-backend-testkey" \
--set "unsealer.args[6]=--google-cloud-kms-location" \
--set "unsealer.args[7]=global" \
--set "unsealer.args[8]=--google-cloud-kms-project" \
--set "unsealer.args[9]=prefab-surfer-263006" \
--set "unsealer.args[10]=--google-cloud-storage-bucket" \
--set "unsealer.args[11]=vault-data-bucket" \
--name vault
```

This will install Vault pod with 4 containers as shown below:

![vault deployed](assets/vault-deployed.jpg?raw=true "vault deployed")


Copying vault root token from Storage Bucket:

```bash
cd ~/github/gcp-vault
echo "Please wait ..............."
gsutil copy gs://vault-data-bucket/vault-root .
gcloud kms decrypt --key=vault-backend-testkey --keyring=vault-backend-testring --location=global --ciphertext-file=vault-root --plaintext-file=vault-root.dec

for i in `cat vault-root.dec`; do export VAULT_TOKEN=$i; done
```

![vault data backend bucket](assets/vault-data-backend-bucket.jpg?raw=true "vault data backend bucket")


Initiating Vault Login:
```bash
echo "Please wait ..............."
sleep 60
export SERVICE_IP=$(kubectl get svc --namespace default vault -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export VAULT_ADDR=https://$SERVICE_IP:8200
export VAULT_SKIP_VERIFY=1

vault status

Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.3.1
Cluster Name             vault-cluster-83ab9435
Cluster ID               cfa20093-a6f3-4800-f527-7d5d25be2f90
HA Enabled               false
```

![gke cluster create](assets/vault-root-token-permissions.jpg?raw=true "gke cluster create")



