# CODE.md — Память проекта Inside

> Этот файл читается агентами (Claude Code, Codex CLI) перед выполнением задач.
> Обновляй его при изменении архитектуры или структуры проекта.

---

## Описание проекта

**Inside** — автономный конвейер разработки, работающий параллельно с проектом Bravo на общей инфраструктуре.

Используется для разработки продукта Inside:
- **Perplexity** создаёт задачи в виде GitHub Issues с детальной спецификацией
- **Claude Code** (Coder) — реализует код по спецификации
- **Codex CLI** (Reviewer + Tester) — ревьюит и тестирует код
- Вся координация через **GitHub Projects v2** (канбан-доска)
- Агенты работают в бесконечном цикле на VPS через systemd

---

## Технологический стек

| Компонент | Технология |
|-----------|-----------|
| Координация задач | GitHub Projects v2 (GraphQL API) |
| Управление кодом | Git + GitHub |
| Кодирование | Claude Code (`claude --print`) |
| Ревью и тестирование | Codex CLI (`codex exec --full-auto`) |
| Автозапуск | systemd unit-файлы |
| API интеграция | `gh` CLI (GitHub CLI) |
| Логирование | `/var/log/inside/` + systemd journal |
| VPS | Contabo (164.68.116.250), пользователь: agent |

---

## Диаграмма конвейера (ASCII)

```
┌─────────────────────────────────────────────────────────────────────┐
│                      GitHub Projects (канбан)                        │
│                                                                       │
│  Backlog → To Do → In Progress → Review → Testing → Done            │
│     │         │          │           │        │        │             │
│     │         │          │           │        │        │             │
│  Perplexity  Human    Claude      Codex    Codex    Human           │
│  (создаёт)  (одобр.) (кодирует)  (ревьюит)(тестир.)(закрывает)    │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
    VPS Contabo (164.68.116.250)
    ├── systemd: inside-coder.service    → pipeline/coder-daemon.sh (Claude)
    ├── systemd: inside-reviewer.service → pipeline/reviewer-daemon.sh (Codex)
    └── systemd: inside-tester.service   → pipeline/tester-daemon.sh (Codex)
```

---

## Описание колонок канбана

| Колонка | ID | Кто управляет | Действие |
|---------|-----|---------------|---------|
| **Backlog** | `5f7f9b84` | Perplexity | Создаёт issue, ждёт одобрения |
| **To Do** | `e04d9225` | Human | Одобрил задачу → Coder берёт |
| **In Progress** | `00ab94fc` | Coder (Claude) | Активная разработка |
| **Review** | `339101c2` | Reviewer (Codex) | Code review + проверка спеки |
| **Testing** | `549f9e5a` | Tester (Codex) | Спека-чеклист + тесты |
| **Done** | `8a4c63f1` | Human | Финальная проверка, закрытие |

---

## Ролевая матрица агентов

| Роль | Daemon | Инструмент | Берёт из | Двигает в | Gate |
|------|--------|-----------|----------|-----------|------|
| **Coder** | `coder-daemon.sh` | Claude Code | To Do | Review | Файлы изменены (`git status`) |
| **Reviewer** | `reviewer-daemon.sh` | Codex CLI | Review | Testing / In Progress | Codex PASS |
| **Tester** | `tester-daemon.sh` | Codex CLI | Testing | Done / In Progress | Codex PASS + тесты |

---

## Конфигурация GitHub Projects

```
Project ID:     PVT_kwHOD_OjOs4BTTC0
Status Field:   PVTSSF_lAHOD_OjOs4BTTC0zhAlFI0
Repo:           ppxtestarena4/inside
Project URL:    https://github.com/users/ppxtestarena4/projects/3
```

Все ID задаются в `pipeline/common.sh` в массиве `COLUMN_IDS`.

---

## Изоляция от Bravo

Inside и Bravo используют одну VPS, но полностью изолированы:

| Параметр | Bravo | Inside |
|----------|-------|--------|
| Репозиторий | ppxtestarena4/bravo | ppxtestarena4/inside |
| GitHub Project | #1 | #3 |
| Логи | `/var/log/bravo/` | `/var/log/inside/` |
| systemd-сервисы | `bravo-*` | `inside-*` |
| Рабочая директория | `/home/agent/bravo/` | `/home/agent/inside/` |
| Ветки | `feature/issue-N` (bravo) | `feature/issue-N` (inside) |

Общие ресурсы: VPS, пользователь `agent`, инструменты (Claude Code, Codex CLI, gh CLI).

---

## Структура репозитория

```
inside/
├── .github/
│   └── ISSUE_TEMPLATE/
│       └── task.md                 # Шаблон issue для задач
├── pipeline/
│   ├── common.sh                   # Общие функции: GraphQL API, логирование
│   ├── coder-daemon.sh             # Агент-программист — Claude Code (бесконечный цикл)
│   ├── reviewer-daemon.sh          # Агент-ревьюер — Codex CLI (бесконечный цикл)
│   ├── tester-daemon.sh            # Агент-тестировщик — Codex CLI (бесконечный цикл)
│   └── install.sh                  # Установщик на VPS
├── systemd/
│   ├── inside-coder.service        # Systemd unit для Coder
│   ├── inside-reviewer.service     # Systemd unit для Reviewer
│   └── inside-tester.service       # Systemd unit для Tester
├── src/                            # Исходный код продукта (заполняется агентами)
├── tests/                          # Тесты (заполняется агентами)
├── CODE.md                         # ← Этот файл (память проекта)
└── README.md                       # Пользовательская документация
```

---

## VPS — детали сервера

```
IP:       164.68.116.250
Пользователь: agent
Домашний каталог: /home/agent/
Репозиторий: /home/agent/inside/
Логи:     /var/log/inside/
```

### Полезные команды на VPS

```bash
# Статус агентов Inside
systemctl status inside-coder inside-reviewer inside-tester

# Логи в реальном времени
journalctl -u inside-coder -f
journalctl -u inside-reviewer -f
journalctl -u inside-tester -f

# Файловые логи
tail -f /var/log/inside/coder.log
tail -f /var/log/inside/reviewer.log
tail -f /var/log/inside/tester.log

# Перезапуск
systemctl restart inside-coder

# Остановить Inside (не затронет Bravo)
systemctl stop inside-coder inside-reviewer inside-tester

# Остановить Bravo (не затронет Inside)
systemctl stop bravo-coder bravo-reviewer bravo-tester
```

---

## Соглашения о коде

- Все bash-скрипты начинаются с `set -euo pipefail`
- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`
- Ссылки на issue в коммитах: `Refs: #N`
- Комментарии в коде — английские, документация — русская
- Логи пишутся через функцию `log()` из `common.sh`

---

*Последнее обновление: 2026-03-31*
