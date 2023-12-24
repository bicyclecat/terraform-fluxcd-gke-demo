# Deploying Infrastructure as Code on Google Cloud GKE with Terraform and FluxCD

## Description:

This demo Terraform project provisions a GKE cluster and bootstraps it with FluxCD, which allows to deploy an application described with Helm-chart stored in a Git Repository, sustain it in desired state and update the used container image if the version of Helm-chart in the code source GitHub repository is changed. It also provides a mechanism of Kubernetes secrets management with Mozilla SOPS.

## Usage:

### 1. Prerequisites:
Mandatory:
- A Google Cloud account
- A Google Cloud Project with set up Google Cloud Billing Account
- A GCS Bucket to backend Terraform remote state (for this demo project, it's "tf-gke-flux-backend")
- All minimum required permissions to create and manage all needed resources in your Google Cloud Project
- GitHub account and GitHub access token with permissions to create repositories and commit changes into them
- GitHub repository which contains a Helm-chart with your application
- Installed Terraform

Optional:
- Installed gcloud utility to work remotely
- Installed FluxCD CLI in order to access FluxCD dashboard and logs
- Installed gpg and SOPS client to encrypt app's Kubernetes secrets

### 2. Login to Google Cloud.
In order to make things start moving, first of all you need to login to your Google Cloud Account, choose your Project and open a terminal session. This can be done by using a web browser to navigate to the Google Cloud Console and log into your account, choosing your Google Cloud Project and running the Cloud Shell.

Also, you can work remotely using any terminal emulator and running the following commands (and follow the instructions they suggest):

```bash
gcloud auth login
```
```bash
gcloud auth application-default login
```
```bash
gcloud config set project <your-project-ID>
```

### 3. Export parameters and values to environment variables

Values and access creadentials to be exported are:

Mandatory:
- GitHub username and access token
- Google Cloud ProjectID and Location

Optional:
- The name of GitHub infrastructure repository which FluxCD will create and use as the source of truth
- The path to FluxCD root infrastructure folder to store your infrastructure manifests (defaults to "clusters")
- GKE Cluster Node number and node VM parameters, i.e. machine type, persistent disk type and size

This can be done like it is shown in the following example (read the warning below)*:
```bash
export \
TF_VAR_GITHUB_OWNER= \
TF_VAR_GITHUB_TOKEN= \
TF_VAR_GOOGLE_PROJECT= \
TF_VAR_GOOGLE_REGION="us-central1-a" \
TF_VAR_FLUX_GITHUB_REPO="fluxcd-gitops" \
TF_VAR_FLUX_GITHUB_TARGET_PATH="clusters" \
TF_VAR_GKE_NUM_NODES=2 \
TF_VAR_GKE_MACHINE_TYPE="e2-small" \
TF_VAR_GKE_DISK_TYPE="pd-standard" \
TF_VAR_GKE_DISK_SIZE_GB=10 \
TF_VAR_SOPS_SECRET_NAME="sops-gpg"
```

__*Important! First three parameters are strictly mandatory, so be sure to fill them up before running the export command.__

All other parameters shown in above example are demo project defaults and can be changed according to your needs and preferrations or omitted at all.

### 4. Initialize, check and apply Terraform plan
To initialize the workspace, run the following command:
```bash
terraform init
```
Then, in order to check terraform plan for errors, run:
```bash
terraform validate
```
To preview all resources which are to be created, run:
```bash
terraform plan
```
Finally, apply the Terraform plan:
```bash
terraform apply
```

After successfull application of Terraform plan, run the following command in order to further interaction with your cluster:
```bash
export KUBECONFIG=$(terraform output -raw kubepath)
```

### 5. Add your App to FluxCD

At this moment, the sructure of your FluxCD infrastructure repository should look like this:
```bash
└─clusters
  └─flux-system
    ├─gotk-components.yaml
    ├─gotk-sync.yaml
    └─kustomization.yaml
```

In order for FluxCD to take your application under its wing, a set of YAML manifests needs to be provided.

Mandatory:
- Namespace definition in order to deploy application in it
- Helm-chart source repository
- Helm-chart specs definition

Optional:
- Kubernetes secrets source repository
- FluxCD kustomization specifying the private key used to decrypt secrets from secrets repository

To perform this step, you need to create your application's subdirectory inside the FluxCD target path in the FluxCD infrastructure GitHub repository and put your App's YAML manifests there. In this demo project, the Application is "kbot" and the target path by default is "clusters", so the the result should look like this:
```bash
└─clusters
  ├─flux-system
  │ ├─gotk-components.yaml
  │ ├─gotk-sync.yaml
  │ └─kustomization.yaml
  └─kbot
    ├─kbot-gr.yaml
    ├─kbot-hr.yaml
    └─kbot-ns.yaml
```

This step can be accomplished by making needed changes in the FluxCD infrastructure GitHub repository using web browser and create-copy-paste-commit YAML files (manifests contents can be copied from corresponding files in demo project's "kbot" directory). Other way is doing this using command line within Google Cloud Shell or any terminal emulator (see the GCloud authorization method described above):

Create a directory that is supposed to represent your FluxCD infrastructure root directory (e.g., "flux-infra") and change into it:
```bash
mkdir flux-infra && cd flux-infra
```

Initialize the directory with your FluxCD infra GitHub repository (replace the placeholders with your actual values):
```bash
git init
git remote add origin https://<GITHUB_USERNAME>:<GITHUB_TOKEN>@github.com/<GITHUB_USERNAME>/<FLUX_GITHUB_REPO>.git
git branch -M main
git pull origin main
```

At this moment, your FluxCD infrastructure directory should look like this:
```bash
└─flux-infra
  └─clusters
    └─flux-system
      ├─gotk-components.yaml
      ├─gotk-sync.yaml
      └─kustomization.yaml
```


Now, it's time to create Application's subdirectory inside FluxCD infrastructure directory and palce YAML files into it.

You can do it fast by running the following commands:
```bash
mkdir clusters/kbot
cp kbot/kbot-ns.yaml kbot/kbot-gr.yaml kbot/kbot-hr.yaml clusters/kbot/
```

Or, YAML manifests can be created in more spectacular way just in command line by running these commands from FluxCD root infrastructure directory ("flux-infra" in our case):

Create "kbot" directory and change into it
```bash
mkdir -p clusters/kbot && cd clusters/kbot
```

Add namespace YAML manifest:
```bash
cat <<EOF > kbot-ns.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: kbot
EOF
```

Add App's code source repository YAML manifest:
```bash
cat <<EOF > kbot-gr.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: kbot-main
  namespace: kbot
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/bicyclecat/kbot
EOF
```

Add Helm-chart specs definition YAML manifest
```bash
cat <<EOF > kbot-hr.yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: kbot
  namespace: kbot
spec:
  chart:
    spec:
      chart: ./helm
      reconcileStrategy: Revision
      sourceRef:
        kind: GitRepository
        name: kbot-main
  interval: 1m0s
EOF
```

At this moment, your FluxCD infrastructure directory should look like this:
```bash
└─flux-infra
  └─clusters
    ├─flux-system
    │ ├─gotk-components.yaml
    │ ├─gotk-sync.yaml
    │ └─kustomization.yaml
    └─kbot
      ├─kbot-gr.yaml
      ├─kbot-hr.yaml
      └─kbot-ns.yaml
```

Change back to your infrastructure root directory and commit changes to your FluxCD infrastructure repository:
```bash
cd ../..
git add .
git commit -m "add Kbot infrastructure manifests"
git push -u origin main
```

After doing the above actions, the sructure of your FluxCD infrastructure repository should look like this:
```bash
└─clusters
  ├─flux-system
  │ ├─gotk-components.yaml
  │ ├─gotk-sync.yaml
  │ └─kustomization.yaml
  └─kbot
    ├─kbot-gr.yaml
    ├─kbot-hr.yaml
    └─kbot-ns.yaml
```

Now, within minutes, FluxCD shall track changes, reconciliate them, and deploy your Application infrastructure into a GKE cluster.

As you could probably notice, the "reconcileStrategy" parameter inside the Helm Release YAML manifest is set to "Revision". That means each time the "Version" parameter of your App's Helm-chart is changed, FluxCD will track that, make reconciliation and update the App's deployment in GKE cluster with newer container image if such is available.

If FluxCD CLI is not installed, you can install it by running this command:
```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

Now you can view FluxCD logs:
```bash
flux logs -f
```

Or, you can view your infrastructure:
```bash
flux get all -A
```

If your application do not use Kubernetes secrets, this could be the end of the demo, but our "Kbot" application needs a secret to store its sensitive data, so we move on to section 6.

## 6. Managing Kubernetes secrets with SOPS encryption

In this demo project, Terraform plan creates a pair of 4096-bit gpg keys.

The public key is stored inside the project root directory in ".sops.pub.asc" file and is used to encrypt your Kubernetes secrets into SOPS-secrets. Next, SOPS-secrets can be placed in any publicly accessed place. In this specific demo project, we are using the specific path ("secrets" by default) inside the Kbot App's GitHub repository.

**Important: the private key file ".sops.pub.asc" must be protected from accidential deletion**

The private key is exported right into FluxCD namespace inside the GKE cluster, and is not stored on a local disk. 

**Important: after destroying and/or re-creating the GKE cluster, all your SOPS-encrypted Kubernetes secrets must be re-encrypted due to private key re-creation**

The following steps need to be performed in order for your Application can access needed Kubernetes secrets.

### 6.1 Secert encryption

If sops utility is not installed, you can follow instructions in the [SOPS Installation guide](https://github.com/getsops/sops)

To encrypt App's Kubernetes secret into SOPS-secret, the provided **sopsify.sh** script can be used. For example, if secret-containing file kbot-token.yaml resides in demo proejct's root directory:
```bash
./sopsify.sh kbot-token.yaml
```
The result is kbot-token-sops.yaml file created alongside your original kbot-token.yaml secret manifest.

### 6.2 Adding secret source repository and Kustomization

As you could probably notice, the "kbot" subdirectory contains also these two YAML files: kbot-secrets-gr.yaml and kbot-secrets-kustomization.yaml.

The first one represent another FluxCD source (GitHub repository presented to FluxCD as "kbot-secrets"), which we use in this demo project to get FluxCD secrets from; In our case, this is the Kbot Application's repository.

The Second one is FluxCD Kustomization, specifying literally this: secrets from "/secrets" path of "kbot-secrets" source should be decrypted with "sops-gpg" FluxCD internal secret (which contains the "sops.asc" private key).

In this demo project, we use kbot-token.yaml which contains App's Kubernetes secret and encrypt it as it described in stage 6.1. After doing so, we put the resulting kbot-token-sops.yaml SOPS-secret manifest file to the location specified in "secrets" subdirectory of "kbot-secrets" FluxCD source (that means, the directory "secrets" must be created in a directory connected to Kbot App GitHub repository, then kbot-token-sops.yaml file put into there and git add/commit/push is supposed to be made, or corresponding actions can be performed using GitHub web interface in a way similar to mentioned before).

Finally, the kbot-secrets-gr.yaml and kbot-secrets-kustomization.yaml manifests should be added to Kbot App's directory within FluxCD infrastructure GitHub repository. This can be performed in several ways, like it is mentioned in section 5.

To add files to FluxCD infrastructure repository using Google Cloud Shell or a terminal emulator on your local machine, you can make it from "flux-infra" subdirectory in a simple way:
```bash
cp kbot/kbot-secrets-gr.yaml kbot/kbot-secrets-kustomization.yaml clusters/kbot/
```
Or on-the-fly:

Change to "kbot" subdirectory
```bash
cd clusters/kbot
```

Add "kbot-secrets" FluxCD source
```bash
cat <<EOF > kbot-secrets-gr.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: kbot-secrets
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/bicyclecat/kbot
EOF
```

Add kbot-secrets Kustomization
```bash
cat <<EOF > kbot-secrets-kustomization.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: kbot-secrets
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: kbot-secrets
  decryption:
    provider: sops
    secretRef:
      name: sops-gpg
  interval: 1m0s
  path: ./secrets
  prune: true

EOF
```

At this moment, your FluxCD infrastructure directory should look like this:
```bash
└─flux-infra
  └─clusters
    ├─flux-system
    │ ├─gotk-components.yaml
    │ ├─gotk-sync.yaml
    │ └─kustomization.yaml
    └─kbot
      ├─kbot-gr.yaml
      ├─kbot-hr.yaml
      ├─kbot-ns.yaml
      ├─kbot-secrets-gr.yaml
      └─kbot-secrets-kustomization.yaml
```

Now, within minutes, FluxCD shall track changes, reconciliate them, get the kbot-token-sops.yaml file from "kbot-secrets" source, decrypt it with "sops-gpg" FluxCD internal secret, obtain the original "kbot-token.yaml" and export it to Kbot App's namespace in the GKE cluster. Voilla! Your Application is up and running now.