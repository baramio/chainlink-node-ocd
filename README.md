# chainlink-node-ocd

Deployment for a 2-node, multi-region Chainlink node using Terraform.

Requirements: terraform.tfvars with the variable values defined.
```
terraform init
terraform plan
terraform apply
```

## Kubernetes Deployment
To make maintanence, upgrades, recovery and even development easier, a deployment script to a Kubernetes cluster is 
also available in the k8s directory. This deployment isn't a multi-region deployment unless the K8s cluster is multi-region.

Requirements: 
* terraform.tfvars with the required variable values
* baramio-kubeconfig.yaml which holds the keys and metadata to deploy to the kubernetes cluster
* terraform to deploy

```
cd k8s
terraform init
terraform plan
terraform apply
```

expose the GUI with port-forwarding - head to the browser and type in localhost:6688 to access the GUI
```
kubectl --kubeconfig ~/.kube/baramio-kubeconfig.yaml port-forward service/chainlink-node 6688:6688 -n chainlink
```