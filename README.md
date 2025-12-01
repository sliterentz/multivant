# Multivant - Multi-Cluster Blue-Green Deployment
This is multi cluster node build with vagrant for blue green development

## About

This project provides a multi-cluster node setup using Vagrant, designed to facilitate blue-green deployment strategies for development and testing environments. It allows developers to create and manage multiple isolated clusters, making it easier to test new features and deployments without affecting a stable environment.

## 🎯 Features

- **Blue-Green Clusters**: Two independent K3s clusters for zero-downtime deployments
- **Platform Lifecycle Planes**:
  - 🔐 Identity Plane (Keycloak, Vault)
  - 🏗️ Build Plane (Jenkins, Harbor, GitLab, ArgoCD)
  - 📊 Observability Plane (Prometheus, Grafana, Loki, Jaeger)
- **WSL2 Support**: Optimized for Windows Subsystem for Linux
- **Modular Architecture**: Clean, maintainable Vagrantfile structure
- **Automated Provisioning**: Ansible-based configuration management

## Prerequisites

Before you begin, ensure you have the following software installed on your system:

- [Vagrant](https://www.vagrantup.com/downloads) >= 2.3.0
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) >= 7.0
- [Git](https://git-scm.com/downloads)

## Components Deployed

This Vagrant setup provisions the following components:
- **Multiple Clusters**: Sets up 'blue' and 'green' clusters to simulate a blue-green environment.
- **Nodes**: Each cluster consists of one or more virtual machine nodes as defined in the `Vagrantfile`.

## Quick Start

Follow these steps to get your multi-cluster environment up and running.

### 1. Install Vagrant on Windows

Download and install Vagrant for Windows from the official website.

[**Download Vagrant**](https://www.vagrantup.com/downloads)

### 2. Install Vagrant Plugin

This project uses the `vagrant-dotenv` plugin to manage environment variables. Open your terminal or PowerShell and run the following command:

```bash
vagrant plugin install vagrant-dotenv
```

### 3. Clone the Repository

```bash
git clone https://github.com/yourusername/myterra.git
cd multivant
```

### 4. Create Shared Folder

```bash
# Run setup script
bash scripts/setup-environment.sh

# Or manually:
cp .env.example .env
mkdir -p shared
```

### 5. Set K3s Token
```bash
bash scripts/generate-token.sh
```

Copy the generated token and add it to your .env file
K3S_TOKEN=your-generated-token-here

### 6. Start the Environment

```bash
vagrant up --provider=virtualbox
```

### 6. Delete Node with Grace (Optional For Redeploy)

```bash
vagrant destroy -g
```