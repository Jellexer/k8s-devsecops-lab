#  DevSecOps Kubernetes Stand

> **Построение DevSecOps-стенда: от уязвимой конфигурации к автоматизированной защите**

Проект демонстрирует полный цикл безопасного деплоя приложения в Kubernetes:
намеренно уязвимая конфигурация → автоматическое сканирование → hardening → Security Gate в GitLab CI.

---

##  Структура репозитория

```
.
├── .gitlab-ci.yml              # Security Gate pipeline
├── .gitignore
│
├── terraform/
│   ├── main.tf                 # 3 ВМ в Yandex Cloud
│   └── meta.txt                # cloud-init: SSH ключ
│
├── manifests/
│   ├── vulnerable/             # намеренно уязвимые
│   │   ├── deployment.yaml     # privileged:true, runAsUser:0, нет лимитов
│   │   └── secret.yaml         # пароли в base64 в репозитории
│   │
│   └── hardened/               # после hardening
│       ├── deployment.yaml     # всё исправлено
│       ├── secret.yaml         # без значений — создаётся через kubectl
│       ├── service.yaml
│       ├── ingress.yaml
│       └── networkpolicy.yaml  # изоляция сетевого доступа
│
├── docs/
│   ├── architecture.md         # схема стенда
│   ├── baseline-results.md     # результаты сканирования до
│   └── hardening-results.md    # результаты после + что исправлено

```

---

##  Стек

| Категория | Инструмент |
|---|---|
| Инфраструктура | Terraform + Yandex Cloud |
| Kubernetes | kubeadm v1.29 |
| Приложение | OWASP Juice Shop |
| SAST | Semgrep |
| Secrets | gitleaks |
| Image scan | Trivy |
| IaC scan | Checkov |
| K8s security | Kubesec |
| CI/CD | GitLab CI |

---

## Развёртывание с нуля

### Требования

- Аккаунт в [Yandex Cloud](https://cloud.yandex.ru)
- Установленный [Terraform](https://developer.hashicorp.com/terraform/downloads)
- SSH ключевая пара
- Аккаунт на [gitlab.com](https://gitlab.com)

---

### Шаг 1 — Настройка Terraform для Yandex Cloud

установить и настроить [yc](https://yandex.cloud/ru/docs/cli/quickstart?utm_referrer=https%3A%2F%2Fgithub.com%2Fbykvaadm%2FCyberEd%2Ftree%2Fmaster%2F1&utm_referrer=https%3A%2F%2Fyandex.cloud%2Fshowcaptchafast%3Fd%3DD401AB14AE73A7FB436A6A7E196D47385A5F1081D374DE656C5F7A704880DF4BD27113A107F764C2F125E467A8C9A0FD17FED58C6A%26retpath%3DaHR0cHM6Ly95YW5kZXguY2xvdWQvcnUvZG9jcy9jbGkvcXVpY2tzdGFydD8mdXRtX3JlZmVycmVyPWh0dHBzJTNBLy9naXRodWIuY29tL2J5a3ZhYWRtL0N5YmVyRWQvdHJlZS9tYXN0ZXIvMQ%252C%252C_fd6a08ca9f4bf46f83a693726e335ad3%26s%3D97754b636669aeb2b056331b07d1c29b)

установить и настроить [terraform](https://yandex.cloud/ru/docs/cli/quickstart?utm_referrer=https%3A%2F%2Fgithub.com%2Fbykvaadm%2FCyberEd%2Ftree%2Fmaster%2F1&utm_referrer=https%3A%2F%2Fyandex.cloud%2Fshowcaptchafast%3Fd%3DD401AB14AE73A7FB436A6A7E196D47385A5F1081D374DE656C5F7A704880DF4BD27113A107F764C2F125E467A8C9A0FD17FED58C6A%26retpath%3DaHR0cHM6Ly95YW5kZXguY2xvdWQvcnUvZG9jcy9jbGkvcXVpY2tzdGFydD8mdXRtX3JlZmVycmVyPWh0dHBzJTNBLy9naXRodWIuY29tL2J5a3ZhYWRtL0N5YmVyRWQvdHJlZS9tYXN0ZXIvMQ%252C%252C_fd6a08ca9f4bf46f83a693726e335ad3%26s%3D97754b636669aeb2b056331b07d1c29b)

---

### Шаг 2 — Поднять ВМ

Подставь свой публичный SSH ключ в `terraform/meta.txt`:


```bash
cd terraform/
terraform init
terraform apply
terraform output  # сохрани все IP
```

---

### Шаг 3 — Настройка master ноды

```bash
ssh debian@MASTER_IP
```

```bash
# Отключить swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Установить containerd
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# Модули ядра
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

# sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# kubeadm + kubelet + kubectl
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Инициализация кластера (подставь MASTER_PRIVATE_IP из terraform output)
sudo kubeadm init \
  --apiserver-advertise-address=MASTER_PRIVATE_IP \
  --pod-network-cidr=10.244.0.0/16

# Настройка kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Flannel — сетевой плагин
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Команда для подключения worker (скопируй, необходима для подключения воркера в кластер)
kubeadm token create --print-join-command
```

---

### Шаг 4 — Настройка worker ноды

```bash
ssh debian@WORKER_IP
```

Повтори все команды из шага 3 кроме `kubeadm init`. Вместо него:

```bash
# Вставь команду с master
sudo kubeadm join MASTER_PRIVATE_IP:6443 --token XXX --discovery-token-ca-cert-hash sha256:XXX
```

---

### Шаг 5 — Проверить кластер

На master:

```bash
kubectl get nodes
# NAME         STATUS   ROLES           VERSION
# k8s-master   Ready    control-plane   v1.29.x
# k8s-worker   Ready    worker          v1.29.x
```

---

### Шаг 6 — Установить Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

---

### Шаг 7 — Настройка git-runner

```bash
ssh debian@RUNNER_IP
```

```bash
# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker debian && newgrp docker

# GitLab Runner
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install -y gitlab-runner
sudo usermod -aG docker gitlab-runner

Зарегистрировать GitLab Runner:

1. gitlab.com → твой проект → Settings → CI/CD → Runners → New project runner
2. Скопируй токен

```bash
sudo gitlab-runner register \
  --non-interactive \
  --url https://gitlab.com \
  --token ВАШ_ТОКЕН \
  --executor docker \
  --docker-image docker:latest \
  --description k8s-devsecops-runner \
  --tag-list git-runner
```

---

### Шаг 8 — Создать секрет в кластере

> Секреты НЕ хранятся в репозитории. Создаются напрямую в кластере.

```bash
kubectl create secret generic juiceshop-secret \
  --from-literal=admin-password=YOUR_SECURE_PASSWORD \
  --from-literal=jwt-secret=YOUR_SECURE_JWT_KEY
```

---

### Шаг 9 — Добавить KUBECONFIG в GitLab

На master:

```bash
cat ~/.kube/config | base64 -w 0
```

В gitlab.com: `Settings → CI/CD → Variables → Add variable`

```
Key:    KUBECONFIG_DATA
Value:  (вставь base64 вывод)
Masked: YES
```

---

### Шаг 10 — Задеплоить приложение

```bash
git clone https://github.com/ТВО_ЮЗЕРНЕЙМ/k8s-devsecops.git
cd k8s-devsecops
kubectl apply -f manifests/hardened/
kubectl get pods

# Узнать порт
kubectl get svc -n ingress-nginx
# Открыть: http://WORKER_IP:PORT
```

---

##  Результаты

| Инструмент | До (vulnerable/) | После (hardened/) |
|---|---|---|
| Kubesec score | **-37** | **+7** |
| gitleaks секреты | 1 | 0 |
| Semgrep находки | 3 | 0 |
| Checkov failed | 22 | 13 |

Подробнее: [Baseline results](docs/baseline-results.md) и [Hardening results](docs/hardening-results.md)

---

##  Security Gate — логика pipeline

```
push
 ├── semgrep    (allow_failure: false) →  блокирует при находках
 ├── gitleaks   (allow_failure: false) →  блокирует при секретах
 ├── trivy      (allow_failure: true)  →  информационно
 ├── kubesec    (allow_failure: false) →  блокирует если score < 0
 ├── checkov    (allow_failure: true)  →  информационно
 └── deploy                            → запускается ТОЛЬКО если всё выше прошло
```


