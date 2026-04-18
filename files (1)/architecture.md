# Архитектура стенда

## Схема

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

## Роли машин

| ВМ | Роль | Описание |
|---|---|---|
| k8s-master | Control plane | kube-apiserver, etcd, scheduler, controller-manager |
| k8s-worker | Data plane | Запускает контейнеры (Juice Shop + Ingress) |
| git-runner | CI/CD | GitLab Runner + все инструменты сканирования |

## Поток данных

```
Разработчик
    │  git push
    ▼
gitlab.com
    │  trigger pipeline
    ▼
git-runner
    ├── semgrep    → сканирует manifests/
    ├── gitleaks   → ищет секреты в manifests/
    ├── trivy      → сканирует Docker образ
    ├── kubesec    → анализирует deployment.yaml
    ├── checkov    → IaC scanning
    └── deploy     → kubectl apply → k8s-master → k8s-worker
```

## Сетевая изоляция (NetworkPolicy)

```
Интернет → Ingress Controller → Juice Shop Pod → DNS (только)
              (ingress-nginx)         ↑
                                 NetworkPolicy
                              (всё остальное заблокировано)
```
