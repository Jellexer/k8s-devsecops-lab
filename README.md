# 🔐 DevSecOps Kubernetes Stand

> **Построение DevSecOps-стенда: от уязвимой конфигурации к автоматизированной защите**

Проект демонстрирует полный цикл безопасного деплоя приложения в Kubernetes:
намеренно уязвимая конфигурация → автоматическое сканирование → hardening → Security Gate в GitLab CI.

---

## 📁 Структура репозитория

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
│   ├── vulnerable/             # ⚠️  Baseline — намеренно уязвимые
│   │   ├── deployment.yaml     # privileged:true, runAsUser:0, нет лимитов
│   │   └── secret.yaml         # пароли в base64 в репозитории
│   │
│   └── hardened/               # ✅  После hardening
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
│
└── screenshots/                # скриншоты для отчёта
```

---

## 📐 Архитектура

```
┌─────────────────────────────────────────────────────┐
│                  Yandex Cloud                        │
│                                                      │
│  ┌─────────────┐        ┌──────────────────────────┐│
│  │  k8s-master │◄──────►│       k8s-worker         ││
│  │ control plane│        │  Juice Shop Pod          ││
│  │  4CPU / 8GB │        │  Ingress Controller      ││
│  └─────────────┘        │  4CPU / 8GB              ││
│                          └──────────────────────────┘│
│                                                      │
│  ┌─────────────┐                                     │
│  │  git-runner │◄──────── gitlab.com                 │
│  │ GitLab Runner│         CI/CD pipeline             │
│  │ 2CPU / 4GB  │                                     │
│  └─────────────┘                                     │
└─────────────────────────────────────────────────────┘
```

| ВМ | Роль | Что делает |
|---|---|---|
| k8s-master | Control plane | Управляет кластером: apiserver, etcd, scheduler |
| k8s-worker | Data plane | Запускает контейнеры (Juice Shop + Ingress) |
| git-runner | CI/CD | Выполняет pipeline, запускает сканеры |

---

## 🛠 Стек

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

## 📖 Теория

### Kubernetes

**Кластер** — группа машин которые работают как единая система под управлением Kubernetes. Ты общаешься с ним через `kubectl` как с единым целым.

**Манифест** — YAML файл с описанием желаемого состояния. `kubectl apply` говорит кластеру "приведи реальность к этому состоянию".

**kubeadm** — инструмент установки кластера. Используется один раз: `kubeadm init` на master, `kubeadm join` на worker.

**kubelet** — постоянный агент на каждой ноде. Слушает master и запускает/останавливает контейнеры.

**containerd** — container runtime. Kubernetes работает с ним напрямую, минуя Docker.

### Зачем модули ядра и sysctl

```
overlay         # файловая система контейнеров
br_netfilter    # сетевые правила между контейнерами

net.ipv4.ip_forward = 1                    # пересылка пакетов между интерфейсами
net.bridge.bridge-nf-call-iptables = 1     # трафик через мосты идёт через iptables
```

Без них сеть между подами не работает.

### Зачем отключать swap

Kubernetes планировщик полагается на гарантированную RAM. Swap делает работу памяти непредсказуемой — планировщик принимает неправильные решения.

### Ingress Controller

Единственная точка входа в кластер. Читает правила из `ingress.yaml` и маршрутизирует HTTP трафик к нужным сервисам. Без него каждому сервису нужен отдельный NodePort.

### NetworkPolicy

По умолчанию все поды в кластере видят друг друга. NetworkPolicy ограничивает с кем может общаться под:
- Juice Shop принимает трафик **только от Ingress Controller**
- Исходящий только DNS — никаких других соединений

### Security Gate

Просто запуск сканеров = **информация**. Security Gate = когда pipeline **физически блокирует деплой** при находках.

```
gitleaks нашёл секрет → exit code 1 → джоба FAILED → deploy НЕ запускается
```

Ключевой параметр: `allow_failure: false` + явный `exit 1` при плохом результате.

---

## 🚀 Развёртывание с нуля

### Требования

- Аккаунт в [Yandex Cloud](https://cloud.yandex.ru)
- Установленный [Terraform](https://developer.hashicorp.com/terraform/downloads)
- SSH ключевая пара
- Аккаунт на [gitlab.com](https://gitlab.com)

---

### Шаг 1 — Настройка Terraform для Yandex Cloud

Настрой зеркало (официальный реестр HashiCorp недоступен в России):

```bash
cat > ~/.terraformrc << 'EOF'
provider_installation {
  network_mirror {
    url     = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
EOF
```

Установи Yandex Cloud CLI и авторизуйся:

```bash
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
yc init
```

Экспортируй переменные:

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=your_cloud_id    # yc config list
export YC_FOLDER_ID=your_folder_id
```

---

### Шаг 2 — Поднять ВМ

Подставь свой публичный SSH ключ в `terraform/meta.txt`:

```bash
cat ~/.ssh/id_rsa.pub
# скопируй вывод в meta.txt вместо ВСТАВЬ_СВОЙ_ПУБЛИЧНЫЙ_КЛЮЧ_СЮДА
```

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

# Команда для подключения worker (скопируй!)
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

# Trivy
wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy

# Kubesec
wget -q https://github.com/controlplaneio/kubesec/releases/download/v2.13.0/kubesec_linux_amd64.tar.gz \
  -O /tmp/kubesec.tar.gz
tar -xzf /tmp/kubesec.tar.gz -C /tmp && sudo mv /tmp/kubesec /usr/local/bin/

# Checkov + Semgrep
sudo apt-get install -y python3-pip
pip3 install checkov semgrep --break-system-packages
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc && source ~/.bashrc

# gitleaks
wget -q https://github.com/gitleaks/gitleaks/releases/download/v8.18.2/gitleaks_8.18.2_linux_x64.tar.gz \
  -O /tmp/gitleaks.tar.gz
tar -xzf /tmp/gitleaks.tar.gz -C /tmp && sudo mv /tmp/gitleaks /usr/local/bin/

# Проверить
trivy --version && kubesec version && checkov --version && semgrep --version && gitleaks version
```

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

> ⚠️ Секреты НЕ хранятся в репозитории. Создаются напрямую в кластере.

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

## 📊 Результаты

| Инструмент | До (vulnerable/) | После (hardened/) |
|---|---|---|
| Kubesec score | **-37** | **+7** |
| gitleaks секреты | 1 | 0 |
| Semgrep находки | 3 | 0 |
| Checkov failed | 22 | 13 |

Подробнее: [docs/baseline-results.md](docs/baseline-results.md) и [docs/hardening-results.md](docs/hardening-results.md)

---

## 🔒 Security Gate — логика pipeline

```
push
 ├── semgrep    (allow_failure: false) → 🔴 блокирует при находках
 ├── gitleaks   (allow_failure: false) → 🔴 блокирует при секретах
 ├── trivy      (allow_failure: true)  → ℹ️  информационно
 ├── kubesec    (allow_failure: false) → 🔴 блокирует если score < 0
 ├── checkov    (allow_failure: true)  → ℹ️  информационно
 └── deploy                            → запускается ТОЛЬКО если всё выше прошло
```

---

## 🗺 Планы по развитию

- **HashiCorp Vault** — управление секретами, ротация
- **Sealed Secrets** — зашифрованные секреты в git
- **RBAC** — минимальные права ServiceAccount
- **Falco** — runtime мониторинг аномалий
- **DefectDojo** — централизованное хранение находок из pipeline
- **OPA Gatekeeper** — политики безопасности кластера

---

## 👤 Автор

Шамсутдинов Артемий — курс «Специалист по безопасной разработке приложений», CyberED 2026
