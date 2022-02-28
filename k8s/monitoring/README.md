Install [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack) in the kubernetes cluster

Apply the ServiceMonitor so prometheus can scrape the Chainlink metrics
```
kubectl --kubeconfig ~/.kube/baramio-kubeconfig.yaml -n kube-prometheus-stack apply -f scrape-chainlink-metrics-node-0.yaml
kubectl --kubeconfig ~/.kube/baramio-kubeconfig.yaml -n kube-prometheus-stack apply -f scrape-chainlink-metrics-node-1.yaml
```

Check the target is added and is being scraped
```
kubectl --kubeconfig ~/.kube/baramio-kubeconfig.yaml port-forward svc/kube-prometheus-stack-prometheus 9090 -n kube-prometheus-stack
```
then on your browser go to `localhost:9090/targets` to verify chainlink is getting scraped

Check Grafana
```
kubectl --kubeconfig ~/.kube/baramio-kubeconfig.yaml port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack
```