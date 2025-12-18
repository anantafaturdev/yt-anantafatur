# StrongSwan Site-to-Site VPN PoC: AWS ↔ GCP

> **Note:** In this PoC, two separate VPCs in AWS and GCP are used. Latency tests and certain configurations (e.g., GCP IP forwarding VMs, AWS/GCP security groups) were not tested.

---

## Recommendations

- Compare costs with **Managed Site-to-Site VPN** before implementation.
- Consider **ARM-based instances** for cost optimization (StrongSwan supports ARM).
- Start with a **small instance type**; it can be resized later.
- Enable **Elastic IP** for public access.

**Performance Benchmark:**

- Total data transferred: **146.0 GB** across 10 runs  
- Average throughput: **~1.91 Gbit/s** with `t4g.micro`

---

## Performance Testing Script

```bash
#!/bin/bash

TARGET_IP="10.0.0.242"
DURATION=60
LOGFILE="vpn_iperf_stress_$(date +%F_%H-%M-%S).log"

while true; do
    iperf3 -c "$TARGET_IP" -t "$DURATION" -P 4 | tee -a "$LOGFILE"
done
````

---

## 1. Network Architecture Overview

```
AWS VPC (10.0.0.0/16) ↔ VPN ↔ GCP VPC (20.0.0.0/16)

AWS VM: 10.0.0.242 (private) / 3.109.85.41 (public)
GCP VM: 20.0.4.187 (private) / 13.233.242.92 (public)
```

---

## 2. Install StrongSwan

### AWS

* Networking → Change source/dest check → **Disable**

### GCP

* Networking → Network interfaces → **IP forwarding ON** (not tested)

```bash
sudo apt update
sudo apt install strongswan strongswan-pki libcharon-extra-plugins -y
```

---

## 3. AWS VM Configuration (`/etc/ipsec.conf`)

```conf
config setup
    charondebug="none"
    uniqueids=yes
    strictcrlpolicy=no

conn %default
    ikelifetime=28800s
    lifetime=3600s
    rekeymargin=540s
    rekeyfuzz=100%
    keyingtries=3
    keyexchange=ikev2
    authby=psk
    mobike=no

conn aws-gcp
    left=10.0.0.242
    leftid=3.109.85.41
    leftsubnet=10.0.0.0/16
    leftauth=psk
    leftfirewall=yes

    right=13.233.242.92
    rightid=13.233.242.92
    rightsubnet=20.0.0.0/16
    rightauth=psk

    auto=start
    type=tunnel
    dpdaction=restart
    dpddelay=30s
    dpdtimeout=120s

    ike=aes256-sha256-modp2048,aes256-sha256-modp3072,aes256-sha256-modp4096!
    esp=aes256-sha256,aes256-sha512,aes256gcm16!
    aggressive=no
    compress=no
    forceencaps=yes
    closeaction=restart
    replay_window=1024
```

---

## 4. GCP VM Configuration (`/etc/ipsec.conf`)

```conf
config setup
    charondebug="none"
    uniqueids=yes
    strictcrlpolicy=no

conn %default
    ikelifetime=28800s
    lifetime=3600s
    rekeymargin=540s
    rekeyfuzz=100%
    keyingtries=3
    keyexchange=ikev2
    authby=psk
    mobike=no

conn gcp-aws
    left=20.0.4.187
    leftid=13.233.242.92
    leftsubnet=20.0.0.0/16
    leftauth=psk
    leftfirewall=yes

    right=3.109.85.41
    rightid=3.109.85.41
    rightsubnet=10.0.0.0/16
    rightauth=psk

    auto=start
    type=tunnel
    dpdaction=restart
    dpddelay=30s
    dpdtimeout=120s

    ike=aes256-sha256-modp2048,aes256-sha256-modp3072,aes256-sha256-modp4096!
    esp=aes256-sha256,aes256-sha512,aes256gcm16!
    aggressive=no
    compress=no
    forceencaps=yes
    closeaction=restart
    replay_window=1024
```

---

## 5. Pre-Shared Key Configuration (`/etc/ipsec.secrets`)

Generate PSK:

```bash
openssl rand -hex 32
# Example output: 1d56325ab9a904027452f4a053c1d7cf6fec4d60d2a077a5ad5d196fc9a81b1c
```

Add to both VMs:

```conf
3.109.85.41 13.233.242.92 : PSK "1d56325ab9a904027452f4a053c1d7cf6fec4d60d2a077a5ad5d196fc9a81b1c"
```

---

## 6. Enable IP Forwarding

```bash
sudo tee -a /etc/sysctl.conf << EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF

sudo sysctl -p
```

---

## 7. Routing Configuration

**AWS Route Table (Main VPC Route Table):**

| Destination | Target      | Status | Propagated |
| ----------- | ----------- | ------ | ---------- |
| 20.0.0.0/16 | eni-xxxxxxx | Active | No         |

**GCP VPC Network Routes:**

| Name       | Destination | Priority | Next hop                 | Network tags |
| ---------- | ----------- | -------- | ------------------------ | ------------ |
| to-aws-vpn | 10.0.0.0/16 | 1000     | Instance: vpn-gateway-vm | vpn-gateway  |

---

## 8. Firewall Rules (Ingress / Security Groups)

> Note: For PoC, all traffic was allowed from anywhere (0.0.0.0/0)

**AWS:**

| Type       | Protocol | Port Range | Source           | Description    |
| ---------- | -------- | ---------- | ---------------- | -------------- |
| Custom UDP | UDP      | 500        | 13.233.242.92/32 | IKE (ISAKMP)   |
| Custom UDP | UDP      | 4500       | 13.233.242.92/32 | NAT-Traversal  |
| Custom ESP | ESP      | All        | 13.233.242.92/32 | IPSec ESP      |
| Custom AH  | AH       | All        | 13.233.242.92/32 | IPSec AH (opt) |

**GCP:**

| Name          | Type    | Protocol | Ports | Source IP      | Target Tags |
| ------------- | ------- | -------- | ----- | -------------- | ----------- |
| ike-inbound   | Ingress | udp      | 500   | 3.109.85.41/32 | vpn-gateway |
| nat-t-inbound | Ingress | udp      | 4500  | 3.109.85.41/32 | vpn-gateway |
| esp-inbound   | Ingress | esp      | all   | 3.109.85.41/32 | vpn-gateway |
| ah-inbound    | Ingress | ah       | all   | 3.109.85.41/32 | vpn-gateway |

---

## 9. Start and Enable StrongSwan

```bash
sudo systemctl restart strongswan-starter
sudo systemctl enable strongswan-starter
```
