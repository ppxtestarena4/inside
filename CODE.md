# CODE.md — Память проекта Inside

> Этот файл читается агентами (Claude Code, Codex CLI) перед выполнением задач.
> Обновляй его при изменении архитектуры или структуры проекта.

---

## Описание проекта

**Inside** — автономный конвейер разработки с чётким разделением ролей.

---

## Поток работы

```
Perplexity (аналитик)     → пишет BRD/спеку           → Backlog
Human (вы)                → проверяет и одобряет       → To Do
Claude Code (кодер)       → реализует по BRD           → Review
Codex CLI (QA)            → ревью + тесты + BRD-check  → Done / To Do
```

### Правила

- **Perplexity** — только аналитик. Пишет BRD и спецификации, создаёт issues.
- **Human** — проверяет спеку, при одобрении двигает Backlog → To Do.
- **Claude Code** — берёт из To Do, кодирует, пушит в ветку, двигает в Review.
- **Codex CLI** — единый QA-агент: code review + тестирование + проверка соответствия BRD.
  - PASS → Done + Pull Request
  - FAIL → возврат в To Do с комментарием (Claude подхватит снова)

---

## Канбан-доска

| Колонка | ID | Кто управляет | Действие |
|---------|-----|---------------|---------|
| **Backlog** | `4b9b609c` | Perplexity | Создаёт BRD/спеку, ждёт одобрения |
| **To Do** | `2d1e5790` | Human → Claude | Human одобряет; Claude берёт задачу |
| **In Progress** | `e475860c` | Claude Code | Активная разработка |
| **Review** | `413316c3` | Codex QA | Ревью + тесты + проверка BRD |
| **Done** | `537bf78f` | Human | Merge PR, финальная проверка |

---

## Ролевая матрица

| Роль | Агент | Инструмент | Берёт из | Двигает в | Gate |
|------|-------|-----------|----------|-----------|------|
| **Аналитик** | Perplexity | — | — | Backlog | BRD написан по шаблону |
| **Кодер** | Claude Code | `claude --print` | To Do | Review | Файлы изменены (`git status`) |
| **QA** | Codex CLI | `codex exec --full-auto` | Review | Done / To Do | VERDICT: PASS/FAIL |

---

## Технологический стек

| Компонент | Технология |
|-----------|-----------|
| Координация задач | GitHub Projects v2 (GraphQL API) |
| Управление кодом | Git + GitHub |
| Кодирование | Claude Code (`claude --print`) |
| QA (ревью + тесты) | Codex CLI (`codex exec --full-auto`) |
| Автозапуск | systemd: `inside-coder` + `inside-qa` |
| API интеграция | `gh` CLI (GitHub CLI) |
| Логирование | `/var/log/inside/` + systemd journal |
| VPS | Contabo (164.68.116.250), пользователь: agent |

---

## Конфигурация GitHub Projects

```
Project ID:     PVT_kwHOD_OjOs4BTTC0
Status Field:   PVTSSF_lAHOD_OjOs4BTTC0zhAlFI0
Repo:           ppxtestarena4/inside
Project URL:    https://github.com/users/ppxtestarena4/projects/3
```

---

## Изоляция от Bravo

| Параметр | Bravo | Inside |
|----------|-------|--------|
| Репозиторий | ppxtestarena4/bravo | ppxtestarena4/inside |
| GitHub Project | #1 | #3 |
| Логи | `/var/log/bravo/` | `/var/log/inside/` |
| systemd-сервисы | `bravo-*` | `inside-coder`, `inside-qa` |
| Рабочая директория | `/home/agent/bravo/` | `/home/agent/inside/` |

Общие ресурсы: VPS, пользователь `agent`, инструменты (Claude Code, Codex CLI, gh CLI).

---

## Структура репозитория

```
inside/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── task.md                 # BRD-шаблон для Perplexity
│   └── workflows/
│       └── codex-review.yml        # Авто-ревью на push/PR
├── pipeline/
│   ├── common.sh                   # Общие функции: GraphQL API, логирование
│   ├── coder-daemon.sh             # Claude Code — кодер (бесконечный цикл)
│   ├── qa-daemon.sh                # Codex CLI — QA: ревью + тесты + BRD (бесконечный цикл)
│   └── install.sh                  # Установщик на VPS
├── systemd/
│   ├── inside-coder.service        # Systemd unit для Claude Coder
│   └── inside-qa.service           # Systemd unit для Codex QA
├── src/                            # Исходный код (заполняется агентами)
├── tests/                          # Тесты (заполняются агентами)
├── CODE.md                         # ← Этот файл
└── README.md                       # Документация
```

---

## Команды на VPS

```bash
# Статус агентов Inside
systemctl status inside-coder inside-qa

# Логи в реальном времени
journalctl -u inside-coder -f
journalctl -u inside-qa -f

# Файловые логи
tail -f /var/log/inside/coder.log
tail -f /var/log/inside/qa.log

# Перезапуск
systemctl restart inside-coder inside-qa

# Остановить Inside (не затронет Bravo)
systemctl stop inside-coder inside-qa
```

---

## Соглашения о коде

- Все bash-скрипты: `set -euo pipefail`
- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`
- Ссылки на issue: `Refs: #N`
- Комментарии в коде — английские, документация — русская
- Логи через функцию `log()` из `common.sh`

---

*Последнее обновление: 2026-03-31*
