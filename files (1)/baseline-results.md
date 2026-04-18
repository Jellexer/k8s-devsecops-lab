# Baseline Scan — результаты до hardening

Манифесты из `manifests/vulnerable/` намеренно содержат уязвимости.

## Kubesec

```
Score: -37

Критические проблемы:
  🔴 privileged == true           — -30 очков
  🔴 allowPrivilegeEscalation == true — -7 очков

Предупреждения (чего не хватает):
  🟡 resources.limits.cpu
  🟡 resources.limits.memory
  🟡 securityContext.runAsNonRoot
  🟡 securityContext.readOnlyRootFilesystem
  🟡 capabilities.drop
```

## gitleaks

```
leaks found: 1

Finding:  jwt-secret: c3VwZXJzZWNyZXRrZXk=
File:     manifests/secret.yaml:12
RuleID:   generic-api-key

Декодируется: echo "c3VwZXJzZWNyZXRrZXk=" | base64 -d => supersecretkey
```

## Semgrep

```
3 Code Findings в manifests/deployment.yaml

  🔴 yaml.kubernetes.security.privileged-container
     privileged: true — контейнер получает привилегии root на хосте

  🔴 yaml.kubernetes.security.allow-privilege-escalation-true
     allowPrivilegeEscalation: true

  🔴 yaml.kubernetes.security.run-as-non-root
     runAsNonRoot не задан — контейнер может запуститься от root
```

## Checkov

```
Passed checks: 71
Failed checks: 22
Skipped checks: 0

Ключевые провалы:
  CKV_K8S_8   — нет Liveness probe
  CKV_K8S_9   — нет Readiness probe
  CKV_K8S_15  — image:latest
  CKV_K8S_20  — нет runAsNonRoot
  CKV_K8S_25  — privileged: true
  CKV_K8S_28  — нет Seccomp профиля
  CKV2_K8S_6  — нет NetworkPolicy
```

## Trivy

```
/juice-shop/lib/insecurity.ts (secrets)
Total: 1 (HIGH: 1, CRITICAL: 0)

HIGH: AsymmetricPrivateKey (private-key)
  RSA Private Key захардкожен в исходном коде приложения
  Файл: insecurity.ts:23
  Используется для подписи JWT токенов
```
