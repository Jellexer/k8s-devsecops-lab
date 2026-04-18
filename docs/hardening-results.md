# Hardening — результаты после

Манифесты из `manifests/hardened/` с применёнными исправлениями.

## Сравнение

| Инструмент | До | После |
|---|---|---|---|
| Kubesec score | **-37** | **+7** |
| gitleaks секреты | 1 | 0 |
| Semgrep находки | 3 | 0 |
| Checkov failed | 22 | 13 |

## Что исправлено

### deployment.yaml

| Параметр | Было | Стало | Почему |
|---|---|---|---|
| `privileged` | true | false | Убрали полный доступ к хосту (-30 kubesec) |
| `runAsUser` | 0 (root) | 1000 | Непривилегированный пользователь |
| `allowPrivilegeEscalation` | true | false | Нельзя повысить привилегии |
| `capabilities.drop` | отсутствует | [ALL] | Минимальные привилегии ядра |
| `resources.limits` | {} | cpu:500m / mem:512Mi | Защита от DoS |
| `image` | latest | v15.0.0 | Фиксированная версия |

### secret.yaml

Пароли убраны из репозитория полностью. Секрет создаётся в кластере:

```bash
kubectl create secret generic juiceshop-secret \
  --from-literal=admin-password=YOUR_PASSWORD \
  --from-literal=jwt-secret=YOUR_JWT_KEY
```

### networkpolicy.yaml (новый файл)

Добавлена сетевая изоляция:
- Ingress: только от namespace `ingress-nginx` на порт 3000
- Egress: только DNS (UDP 53)

## Kubesec после hardening

```
Score: +7

Passed:
  LimitsCPU       +1
  LimitsMemory    +1
  RequestsCPU     +1
  RequestsMemory  +1
  CapDropAny      +1
  ReadOnlyRootFilesystem (частично)
```

## Оставшиеся 13 Checkov failed

Сознательные архитектурные решения:
- `CKV_K8S_21` — используется namespace `default` (для учебного стенда приемлемо)
- `CKV_K8S_28` — нет Seccomp профиля (требует отдельной настройки)
- `CKV_K8S_30` — нет AppArmor профиля (требует настройки на каждой ноде)
- `readOnlyRootFilesystem: false` — Juice Shop требует запись временных файлов
