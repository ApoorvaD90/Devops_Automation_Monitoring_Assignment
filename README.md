# MERN Stack Deployment on AWS — Terraform & Ansible

Capstone assignment for the DevOps module: provisioning AWS infrastructure with **Terraform** and configuring/deploying the **TravelMemory** MERN application with **Ansible**.

- **Application deployed:** [TravelMemory](https://github.com/UnpredictablePrashant/TravelMemory) (MERN stack travel diary app)
- **Author:** Apoorva Deshpande

## Repository Structure

```
.
├── mern-terraform/          # Terraform infrastructure code
│   ├── main.tf              # Provider configuration
│   ├── variables.tf         # Input variables
│   ├── vpc.tf                # VPC, subnets, IGW, NAT gateway, route tables
│   ├── security_groups.tf   # Security groups for web & DB servers
│   ├── iam.tf                # IAM role + instance profile for EC2
│   ├── ec2.tf                 # Web server & DB server EC2 instances
│   └── outputs.tf            # Public/private IP outputs
└── mern-ansible/             # Ansible configuration & playbooks
    ├── ansible.cfg            # Ansible defaults (inventory, SSH key, user)
    ├── inventory.ini          # Web + DB server inventory (DB reached via bastion)
    ├── dbserver.yml           # MongoDB install & configuration playbook
    ├── webserver.yml          # Node.js/React/Nginx deployment playbook
    └── security_hardening.yml # UFW + SSH hardening playbook
```

## Architecture Overview

```
                                Internet
                                   │
                          Internet Gateway
                                   │
                    ┌──────────────────────────────┐
                    │      VPC (10.0.0.0/16)        │
                    │                                │
                    │  Public Subnet (10.0.1.0/24)   │
                    │  ┌──────────────────────────┐  │
                    │  │  Web Server (EC2)         │  │
                    │  │  Nginx :80  ── proxy ──▶  │  │
                    │  │  Node/Express :3000        │  │
                    │  │  React build (static)      │  │
                    │  └───────────┬──────────────┘  │
                    │              │ SSH bastion       │
                    │              │ MongoDB :27017     │
                    │  Private Subnet (10.0.2.0/24)    │
                    │  ┌──────────────────────────┐  │
                    │  │  DB Server (EC2)           │  │
                    │  │  MongoDB 7.0 :27017        │  │
                    │  └──────────────────────────┘  │
                    │              │                   │
                    │         NAT Gateway (outbound)   │
                    └──────────────────────────────────┘
```

- The **web server** sits in the public subnet, has a public IP, and runs Nginx (port 80), which serves the React production build and reverse-proxies `/api` calls to the Node/Express backend (port 3000, managed by PM2).
- The **DB server** sits in the private subnet with **no public IP**, running MongoDB. It only accepts SSH and MongoDB (27017) traffic from the web server's security group.
- The **NAT Gateway** lets the private DB server reach the internet outbound (e.g. for `apt` package installs) without allowing any inbound connections from the internet.
- Ansible reaches the DB server by **SSH ProxyJump/ProxyCommand through the web server**, since it has no direct route from the local machine.

---

## Prerequisites

Install on your local Windows machine:

| Tool | Purpose | Verify |
|---|---|---|
| [AWS CLI v2](https://awscli.amazonaws.com/AWSCLIV2.msi) | Authenticate & interact with AWS | `aws --version` |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | Provision AWS infrastructure | `terraform --version` |
| Ansible (via WSL, since it doesn't run natively on Windows) | Configuration management | `ansible --version` |

### Install Ansible via WSL

```powershell
wsl --install
```

Then inside the WSL terminal:

```bash
sudo apt update
sudo apt install -y ansible
ansible --version
```

(Alternatively, Ansible can be installed and run directly from the EC2 web server itself.)

---

## Part 1 — AWS CLI Setup

1. **Create an IAM user** in the AWS Console → IAM → Users → Create User
   - Name: `terraform-user`
   - Attach policy: `AdministratorAccess`
   - Create an access key of type **Command Line Interface (CLI)** and save the Access Key ID / Secret Access Key.

2. **Configure the AWS CLI:**

   ```powershell
   aws configure
   ```

   | Field | Value |
   |---|---|
   | AWS Access Key ID | *your access key* |
   | AWS Secret Access Key | *your secret key* |
   | Default region name | `us-east-1` |
   | Default output format | `json` |

3. **Verify:**

   ```powershell
   aws sts get-caller-identity
   ```

---

## Part 2 — Terraform Infrastructure Setup

All Terraform code lives in [`mern-terraform/`](mern-terraform/).

### 2.1 What gets provisioned

| File | Resources |
|---|---|
| `main.tf` | AWS provider (`~> 5.0`), region from `var.aws_region` |
| `variables.tf` | `aws_region`, `vpc_cidr`, `public_subnet_cidr`, `private_subnet_cidr`, `instance_type` (`t3.micro`), `key_name` (`mern-key`), `my_ip` |
| `vpc.tf` | VPC (`10.0.0.0/16`), public subnet (`10.0.1.0/24`), private subnet (`10.0.2.0/24`), Internet Gateway, Elastic IP + NAT Gateway, public/private route tables and associations |
| `security_groups.tf` | `mern-web-sg` (SSH from `my_ip`, HTTP 80, HTTPS 443, Node 3000, React 3001, all egress); `mern-db-sg` (SSH & MongoDB 27017 only from `mern-web-sg`, all egress) |
| `iam.tf` | `mern-ec2-role` (EC2 assume-role), `AmazonSSMManagedInstanceCore` policy attachment, `mern-ec2-profile` instance profile |
| `ec2.tf` | Latest Ubuntu 22.04 AMI lookup; `mern-web-server` (public subnet) and `mern-db-server` (private subnet), both `t3.micro`, both using `mern-web-sg`/`mern-db-sg` and the shared IAM instance profile |
| `outputs.tf` | `web_server_public_ip`, `web_server_public_dns`, `db_server_private_ip`, `vpc_id` |

### 2.2 Before running

Create an EC2 key pair named **`mern-key`** in the AWS Console (EC2 → Key Pairs → Create Key Pair) and download the `.pem` file — Terraform references this key name and Ansible uses the private key for SSH.

### 2.3 Deploy

```powershell
cd mern-terraform
terraform init      # download the AWS provider
terraform plan       # preview resources to be created
terraform apply      # provision VPC, subnets, gateways, SGs, IAM, EC2 (type 'yes' to confirm)
```

### 2.4 Record the outputs

After `apply` finishes, Terraform prints:

```
web_server_public_ip  = "<WEB_SERVER_PUBLIC_IP>"
web_server_public_dns = "<WEB_SERVER_PUBLIC_DNS>"
db_server_private_ip  = "<DB_SERVER_PRIVATE_IP>"
vpc_id                = "<VPC_ID>"
```

Save the public IP and private IP — they feed directly into the Ansible inventory in Part 3.

---

## Part 3 — Ansible Configuration & Deployment

All Ansible code lives in [`mern-ansible/`](mern-ansible/).

### 3.1 Copy the SSH key and configure Ansible

```bash
cp mern-key.pem ~/.ssh/mern-key.pem
chmod 400 ~/.ssh/mern-key.pem
```

`ansible.cfg` sets the inventory file, remote user (`ubuntu`), private key path, and disables strict host-key checking for first connection.

### 3.2 Populate the inventory

Edit `inventory.ini` and replace the placeholders with the Terraform outputs:

```ini
[webserver]
web ansible_host=<WEB_SERVER_PUBLIC_IP>

[dbserver]
db ansible_host=<DB_SERVER_PRIVATE_IP> ansible_ssh_common_args='-o ProxyJump=ubuntu@<WEB_SERVER_PUBLIC_IP>'

[webserver:vars]
ansible_python_interpreter=/usr/bin/python3

[dbserver:vars]
ansible_python_interpreter=/usr/bin/python3
```

The `ProxyJump` (equivalently a `ProxyCommand`) routes the SSH connection to the private DB server **through the public web server acting as a bastion host**, since the DB server has no public IP.

Also update the hard-coded `db_host` variable inside `webserver.yml` to match the DB server's private IP.

### 3.3 Test connectivity

```bash
ansible all -m ping
```

Expected:

```
web | SUCCESS => {"ping": "pong"}
db  | SUCCESS => {"ping": "pong"}
```

### 3.4 Run the playbooks (in order)

```bash
# 1. Database first, so MongoDB is ready before the backend connects
ansible-playbook dbserver.yml

# 2. Web server: Node.js, PM2, clone repo, install deps, build, Nginx
ansible-playbook webserver.yml

# 3. Security hardening on both servers
ansible-playbook security_hardening.yml
```

Each run should end with a `PLAY RECAP` showing `failed=0`.

### 3.5 What each playbook does

**`dbserver.yml`** (target: `dbserver`)
- Installs `gnupg`/`curl`, adds the MongoDB 7.0 GPG key and APT repository, installs `mongodb-org`
- Starts and enables `mongod`, waits for port 27017
- Creates a MongoDB **admin** user (root role) and an **application** user (`traveluser`, `readWrite` on the `travelmemory` database)
- Configures `bindIp: 0.0.0.0` in `mongod.conf` so it accepts connections from the web server, then restarts `mongod`

**`webserver.yml`** (target: `webserver`)
- Installs `curl`, `git`, `nginx`
- Installs Node.js 18.x from NodeSource and PM2 globally
- Clones the [TravelMemory](https://github.com/UnpredictablePrashant/TravelMemory) repo into `/home/ubuntu/TravelMemory`
- Installs backend dependencies and writes `backend/.env` with `MONGO_URI` (pointing at the DB server's private IP) and `PORT=3000`
- Starts the backend with **PM2** (`pm2 start index.js --name backend`, `pm2 save`) as the `ubuntu` user
- Installs frontend dependencies, writes `frontend/.env` with `REACT_APP_BACKEND_URL`, and builds the React app (`CI=false` to stop CRA warnings from failing the build)
- Configures Nginx to serve the React build as static files at `/` and reverse-proxy `/api` to the Express backend on port 3000; removes the default Nginx site and restarts Nginx
- Sets up PM2 to persist across reboots (`pm2 startup`)

**`security_hardening.yml`** (targets: `webserver` and `dbserver`)
- Installs and enables **UFW**, default-denies inbound / allows outbound
  - Web server: allows 22, 80, 443, 3000
  - DB server: allows 22 and 27017 (scoped to the private subnet CIDR `10.0.1.0/24`)
- Disables `PermitRootLogin` and `PasswordAuthentication` in `sshd_config` on both servers (SSH key-only access)
- Restarts the `ssh` service
- Fixes `~/.ssh` (0700) and `~/.ssh/authorized_keys` (0600) permissions on the web server
- Drops the MongoDB `test` database on the DB server as a final cleanup step

---

## Part 4 — Verify the Application

**Backend (on the web server):**

```bash
pm2 status
pm2 logs backend
curl http://localhost:3000
```

**Frontend:** open `http://<WEB_SERVER_PUBLIC_IP>` in a browser — the TravelMemory React app should load and be able to create/view trips (confirming it can reach the Express API, which in turn reaches MongoDB).

**Database (via the web server as bastion):**

```bash
ssh -i ~/.ssh/mern-key.pem -J ubuntu@<WEB_SERVER_PUBLIC_IP> ubuntu@<DB_SERVER_PRIVATE_IP>
sudo systemctl status mongod
mongosh --eval "db.adminCommand('ping')"
```

**Firewalls:**

```bash
sudo ufw status verbose   # run on both web and DB servers
```

---

## Cleanup

To avoid ongoing AWS charges, destroy all provisioned resources once you're done:

```powershell
cd mern-terraform
terraform destroy
```

Type `yes` when prompted. This removes the VPC, subnets, gateways, security groups, IAM role/profile, and both EC2 instances.

---

# Implementation Report

## 1. Project Overview

| | |
|---|---|
| **Assignment** | MERN Stack Deployment on AWS using Terraform and Ansible |
| **Application** | [TravelMemory](https://github.com/UnpredictablePrashant/TravelMemory) — a MERN stack travel diary application |
| **Tools used** | Terraform, Ansible, AWS (VPC, EC2, IAM, NAT Gateway), MongoDB 7.0, Node.js 18, React, Nginx, PM2, UFW |
| **Region** | `us-east-1` |

## 2. Infrastructure Architecture

Provisioned via Terraform (`mern-terraform/`):

| Resource | Details |
|---|---|
| VPC | `10.0.0.0/16` — isolated network for all resources |
| Public Subnet | `10.0.1.0/24` — hosts the web server; internet-reachable |
| Private Subnet | `10.0.2.0/24` — hosts the DB server; no direct internet access |
| Internet Gateway | Allows the public subnet to reach/be reached from the internet |
| NAT Gateway (+ EIP) | Sits in the public subnet; lets the private subnet initiate outbound connections (e.g. package installs) without any inbound exposure |
| Route Tables | Public route table → IGW (`0.0.0.0/0`); private route table → NAT Gateway (`0.0.0.0/0`) |
| Web Server EC2 | `t3.micro`, Ubuntu 22.04 (latest AMI via `data.aws_ami`), public subnet, key pair `mern-key` |
| DB Server EC2 | `t3.micro`, Ubuntu 22.04, private subnet, key pair `mern-key` |
| `mern-web-sg` | Inbound: SSH (22) from operator IP only, HTTP (80), HTTPS (443), Node backend (3000), React dev port (3001); all egress |
| `mern-db-sg` | Inbound: SSH (22) and MongoDB (27017) **only** from `mern-web-sg`; all egress |
| IAM Role / Instance Profile | `mern-ec2-role` with `AmazonSSMManagedInstanceCore` attached, exposed to both instances via `mern-ec2-profile` |

**Actual deployed values from this run** (infrastructure has since been torn down with `terraform destroy` to avoid ongoing AWS charges):
- Web server public IP: `18.215.185.237`
- DB server private IP: `10.0.2.15`

## 3. How the Application Components Interact

```
User (Browser)
      │  HTTP :80
      ▼
Nginx (Web Server, public subnet)
  ├── /            → serves React static build (frontend/build)
  └── /api         → reverse-proxied to ──▶ Node/Express backend :3000 (PM2-managed)
                                                   │
                                                   │ MongoDB URI: mongodb://traveluser:***@<db_private_ip>:27017/travelmemory
                                                   ▼
                                      MongoDB 7.0 (DB Server, private subnet, :27017)
```

- The **user** hits the web server's public IP on port 80.
- **Nginx** serves the pre-built React static files directly, and proxies any `/api/*` request to the Node/Express backend running locally on port 3000.
- The **Express backend** (kept alive by **PM2**, which auto-restarts it on crash/reboot) connects to **MongoDB** using the DB server's private IP over port 27017 — this connection never leaves the VPC.
- **MongoDB** has no public IP and only accepts connections from the web server's security group, enforced both at the AWS security-group layer and the OS-level UFW firewall.
- Both servers only accept inbound SSH from an authorized source (operator IP for the web server; the web server itself for the DB server, via bastion/ProxyJump), and only via SSH key — password auth and root login are disabled.

## 4. Terraform Implementation Summary

| File | Purpose |
|---|---|
| `main.tf` | AWS provider block, pinned to `~> 5.0` |
| `variables.tf` | Centralizes region, CIDRs, instance type, key pair name, operator IP |
| `vpc.tf` | VPC, public/private subnets, IGW, EIP + NAT Gateway, route tables & associations |
| `security_groups.tf` | Web and DB security groups |
| `iam.tf` | EC2 IAM role, SSM policy attachment, instance profile |
| `ec2.tf` | Ubuntu 22.04 AMI lookup, web server instance, DB server instance |
| `outputs.tf` | Public IP/DNS of web server, private IP of DB server, VPC ID |

Commands run:

```bash
terraform init    # download the AWS provider plugin
terraform plan     # preview resources to be created
terraform apply    # create all resources in AWS
```

## 5. Ansible Implementation Summary

| Playbook | Target | What it does |
|---|---|---|
| `dbserver.yml` | DB Server | Installs MongoDB 7.0, creates admin + application (`traveluser`) users scoped to the `travelmemory` database, binds MongoDB to all interfaces so the web server can reach it |
| `webserver.yml` | Web Server | Installs Node.js 18.x, PM2, Nginx; clones TravelMemory; installs backend & frontend dependencies; writes `.env` files for both; builds the React app; configures Nginx as a static file server + reverse proxy; starts the backend under PM2 |
| `security_hardening.yml` | Both servers | Installs/enables UFW with least-privilege inbound rules; disables root SSH login and password authentication; fixes SSH directory/file permissions; drops the MongoDB `test` database |

Ansible connects to the web server directly over SSH. The DB server, being in the private subnet with no public IP, is reached by **ProxyJump through the web server** acting as a bastion host.

## 6. Security Measures Implemented

- **Network isolation:** DB server lives in a private subnet with no public IP; only reachable from the VPC.
- **Security groups:** Least-privilege inbound rules — DB security group only accepts traffic from the web security group, not from arbitrary CIDRs.
- **OS-level firewall (UFW):** Enforces the same port restrictions at the instance level as a defense-in-depth measure on top of AWS security groups.
- **SSH hardening:** Root login disabled, password authentication disabled — key-pair (`mern-key`) access only.
- **MongoDB authentication:** Dedicated application user with `readWrite` scoped only to the `travelmemory` database (not a shared admin credential); admin/root user kept separate.
- **NAT Gateway:** Private subnet resources can reach the internet for outbound package installs but cannot be reached from the internet.
- **IAM least privilege via instance profile:** EC2 instances assume a dedicated role (SSM managed-instance access) rather than embedding long-lived credentials on the boxes.

## 7. Challenges and Solutions

| Challenge | Solution |
|---|---|
| `terraform apply` failed looking for a key pair | Created the `mern-key` EC2 key pair in the AWS Console *before* running `terraform apply`, since Terraform references it by name but doesn't create it |
| Backend couldn't reach MongoDB from the web server | Set `bindIp: 0.0.0.0` in `mongod.conf` on the DB server and restarted `mongod`, while still restricting access at the security-group/UFW layer |
| Avoiding idle AWS costs after verification | Ran `terraform destroy` once the deployment was verified end-to-end, tearing down the VPC, EC2 instances, NAT Gateway, and all associated resources |

## 8. Screenshots / Demonstration

The following were captured during the deployment to demonstrate a working end-to-end setup (see submission attachments):

1. `terraform plan` output
2. `terraform apply` output showing resources created
3. Terraform outputs (web server public IP, DB server private IP)
4. VPC created in the AWS Console
5. Two EC2 instances running (web + DB)
6. Security groups configured in the AWS Console
7. `ansible all -m ping` success for both hosts
8. `ansible-playbook dbserver.yml` success output
9. `ansible-playbook webserver.yml` success output
10. TravelMemory app running in the browser at the web server's public IP
11. `pm2 status` showing the backend process running on the web server
12. `systemctl status mongod` on the DB server
13. `ansible-playbook security_hardening.yml` success output
14. `sudo ufw status verbose` on the web server
15. `sudo ufw status verbose` on the DB server
