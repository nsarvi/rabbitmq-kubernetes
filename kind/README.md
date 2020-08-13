# Install of RabbitMQ on Kind kubernetes cluster

The main goal of this document is to setup a quick RabbitMQ cluster on 4 node Kubernetes cluster, set up monitoring using Prometheus, Grafana and run workloads to confirm the metrics are displayed on Grafana dashboard.


## Create 4 node kubernetes cluster
Kubernetes version used is 1.7 as current version of RabbitMQ 3.6 doesn't support K8s 1.8 fully yet.

`kind create cluster --name rmq-cluster --config rabbitmq-3node-kind.yaml`

## Clone RMQ operator
This is an optional step. Lately, RMQ core team is pushing images to docker

`git clone https://github.com/rabbitmq/cluster-operator.git`

### Build the image

cd cluster-operator
`docker build -t nsarvi/rmq-cluster-operator:1.0 .`

### Push the image

`docker push nsarvi/rmq-cluster-operator:1.0`

## Install Operator

Prepare rmq-cluster-operator.yaml with latest pushed rmq-operator image with docker hub credentials.

`helm -n default install -f rmq-cluster-operator-values.yaml cluster-operator cluster-operator/charts/operator/`

Make sure that operator is installed correctly by running the following command

`k get crds rabbitmqclusters.rabbitmq.com`. This should display the below

`rabbitmqclusters.rabbitmq.com   2020-08-13T15:58:44Z`

### create 3-node RMQ Cluster

You can customize RMQ pod for various configurations, check out the operator document for supported options.

`k create -f rabbitmq-3pod.yaml`

## Install prometheus operator

This document follows Promtheus operator way of installing Promtheus. Checkout the latest prometheus
Per the support matrix of Prometheus, Promtheus operator release-0.4 is supported on K8s 1.17.

`git clone https://github.com/prometheus-operator/kube-prometheus.git
cd kube-prometheus
git checkout -b release-0.4`

Install various components such as podmonitor, servicemonitor etc.

`kubectl create -f ~/kube-prometheus/manifests/setup
until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
kubectl create -f ~/kube-prometheus/manifests/`

Check if  crds for podmonitor, alertmanager are all created using below command.

`k get crds podmonitors.monitoring.coreos.com servicemonitors.monitoring.coreos.com`

## Enable prometheus operator to monitor Rabbit cluster

`kubectl apply -f ./prometheus/rabbitmq-podmonitor.yaml
kubectl apply -f ./prometheus/rabbitmq-servicemonitor.yaml
kubectl apply -f ./prometheus/prometheus-roles.yaml`

## Expose ports
This method follows the ClusterIP, so we are port-forwarding to access RabbitMQ management, Grafana and Promtheus UI

`instance=$(kubectl get RabbitmqCluster -o yaml -o jsonpath="{ .items[0]['metadata.name'] }")
 kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090
 kubectl --namespace monitoring port-forward svc/grafana 3000`

Access management URL
`kubectl port-forward svc/${instance}-rabbitmq-client 15672`

## Run a workload, within a cluster

`instance=$(kubectl get RabbitmqCluster -o yaml -o jsonpath="{ .items[0]['metadata.name'] }")
 username=$(kubectl get secret ${instance}-rabbitmq-admin -o jsonpath="{.data.username}" | base64 --decode)
 password=$(kubectl get secret ${instance}-rabbitmq-admin -o jsonpath="{.data.password}" | base64 --decode)
 service=${instance}-rabbitmq-client
 kubectl run perf-test --image=pivotalrabbitmq/perf-test -- --uri "amqp://${username}:${password}@${service}"`

 Run a test connecting externally from

`kubectl port-forward svc/${instance}-rabbitmq-client 5672`


## Metrics
Locally, we can test if the metrics are getting through the plugin.

`kubectl --namespace monitoring port-forward ${instance}-rabbitmq-client 15692`

Access the UI or curl command

 http://localhost:15692/metrics

 `curl -s localhost:15692/metrics`

## Clean up prometheus and operator
for n in $(kubectl get namespaces -o jsonpath={..metadata.name}); do
  kubectl delete --all --namespace=$n prometheus,servicemonitor,podmonitor,alertmanager
done

kubectl delete -f ~/prometheus-operator/bundle.yaml

kubectl delete --ignore-not-found=true -f ~/kube-prometheus/manifests/ -f ~/kube-prometheus/manifests/setup
