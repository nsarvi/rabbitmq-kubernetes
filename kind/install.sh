# create a kind cluster
# Kubernetes version used is 1.7 as it doesn't support 1.8 yet
# Installs 3.8.5 version

kind create cluster --name rmq-cluster --config rabbitmq-3node-kind.yaml

#clone the RMQ operator
git clone https://github.com/rabbitmq/cluster-operator.git

# build the image
cd cluster-operator
docker build -t nsarvi/rmq-cluster-operator:1.0 .

# push the image
docker push nsarvi/rmq-cluster-operator:1.0

# Prepare rmq-cluster-operator.yaml with latest pushed rmq-operatorimage
# install Operator
helm -n default install -f rmq-cluster-operator-values.yaml cluster-operator cluster-operator/charts/operator/

# create 3-node RMQ Cluster
k create -f rabbitmq-3pod.yaml

# Install prometheus operator
# Kube-Promtheus
git clone https://github.com/prometheus-operator/kube-prometheus.git
cd kube-prometheus
git checkout -b release-0.4

kubectl create -f ~/kube-prometheus/manifests/setup
until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
kubectl create -f ~/kube-prometheus/manifests/

# check the crds for podmonitor, alertmanager are all created now.



# Enable prometheus operator to monitor Rabbit cluster
kubectl apply -f ../prometheus/rabbitmq-podmonitor.yaml
kubectl apply -f ../prometheus/prometheus-roles.yaml


 # Expose ports
 instance=$(kubectl get RabbitmqCluster -o yaml -o jsonpath="{ .items[0]['metadata.name'] }")
 kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090
 kubectl --namespace monitoring port-forward svc/grafana 3000
 # Access management URL
 kubectl port-forward svc/${instance}-rabbitmq-client 15672

 # Run a workload, within a cluster
 instance=$(kubectl get RabbitmqCluster -o yaml -o jsonpath="{ .items[0]['metadata.name'] }")
 username=$(kubectl get secret ${instance}-rabbitmq-admin -o jsonpath="{.data.username}" | base64 --decode)
 password=$(kubectl get secret ${instance}-rabbitmq-admin -o jsonpath="{.data.password}" | base64 --decode)
 service=${instance}-rabbitmq-client
 kubectl run perf-test --image=pivotalrabbitmq/perf-test -- --uri "amqp://${username}:${password}@${service}"

# Run a test connecting externally from
kubectl port-forward svc/${instance}-rabbitmq-client 5672


# Test Metrics
kubectl --namespace monitoring port-forward ${instance}-rabbitmq-client 15692
# http://localhost:15692/metrics

# Clean up prometheus and operator
for n in $(kubectl get namespaces -o jsonpath={..metadata.name}); do
  kubectl delete --all --namespace=$n prometheus,servicemonitor,podmonitor,alertmanager
done

kubectl delete -f ~/prometheus-operator/bundle.yaml

kubectl delete --ignore-not-found=true -f ~/kube-prometheus/manifests/ -f ~/kube-prometheus/manifests/setup

# end
