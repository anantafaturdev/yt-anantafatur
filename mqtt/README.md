# Mosquitto MQTT Broker on Kubernetes

This repository contains Kubernetes manifests and instructions for deploying a Mosquitto MQTT broker to handle communication between apps running on a Kubernetes cluster and IoT devices on the edge.

---

## 🔹 Exposure Methods Overview

There are multiple ways to expose a service in Kubernetes:

* **NodePort**: Opens a specific port on all cluster nodes. Clients can reach the broker via `<node-ip>:<nodePort>`. Simple and suitable for development or internal use.
* **TCP Ingress Controller**: Centralized entry point, supports TCP routing. Useful for multiple services sharing one ingress. Requires manual TLS/certificate management.
* **External LoadBalancer**: Assigns a public IP using cloud provider's load balancer. Best for production scenarios, easier external access, and provider-managed security features.

**Chosen Method**: NodePort, because it is simple, easy to set up, and sufficient for development or proof-of-concept use. For cloud or production use, a TCP Ingress or External LoadBalancer would be preferred.

---

## 🔹 Deployment Instructions

### 1. Apply the manifest

```bash
kubectl apply -f mosquitto-manifest.yaml
```

This manifest includes:

* `ConfigMap` for Mosquitto configuration and password
* `PersistentVolumeClaim` for `/mosquitto/data`
* `Deployment` for Mosquitto container with resource requests/limits
* `Service` of type NodePort (default nodePort: 30083)

### 2. Verify deployment

```bash
kubectl get pods
kubectl get svc
kubectl describe pod <mosquitto-pod-name>
```

---

## 🔹 Connect to the Broker

1. Find a node IP in the cluster:

```bash
kubectl get nodes -o wide
```

2. Use `<node-ip>:30083` as the broker address in the MQTT client.
3. Use the configured username/password (from `mosquitto-password` ConfigMap).

Example using `mosquitto_pub` and `mosquitto_sub`:

```bash
# Subscribe to topic 'test'
mosquitto_sub -h <node-ip> -p 30083 -t test -u mqtt -P mqtt

# Publish to topic 'test'
mosquitto_pub -h <node-ip> -p 30083 -t test -m "Hello from K8s" -u mqtt -P mqtt
```

---

## 🔹 Notes

* Resource requests/limits are configured for lightweight operation; autoscaling (HPA/VPA) can be considered in production environments.

---

## 📚 Reference

[https://blog.quadmeup.com/2025/07/09/mosquitto-in-kubernetes-the-simple-way](https://blog.quadmeup.com/2025/07/09/mosquitto-in-kubernetes-the-simple-way/)
