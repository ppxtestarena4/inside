# CODE.md — Память проекта inside

> Этот файл читается Codex-агентами перед выполнением задач.
> Обновляй его при изменении архитектуры или структуры проекта.

---

## Описание проекта

**inside** — универсальный шаблон автономного конвейера разработки на основе трёх Codex-агентов.

Используется для любого проекта, которому нужна автоматизированная разработка:
- Perplexity (или человек) создаёт задачи в виде GitHub Issues с детальной спецификацией
- Три Codex-агента (`Coder`, `Reviewer`, `Tester`) выполняют, проверяют и тестируют задачи автоматически
- Вся координация происходит через GitHub Projects (канбан-доска)
- Агенты работают в бесконечном цикле на VPS через systemd

---

## Технологический стек

| Компонент | Технология |
|-----------|-----------|
| Координация задач | GitHub Projects v2 (GraphQL API) |
| Управление кодом | Git + GitHub |
| Исполнение агентов | Codex CLI (`codex exec --full-auto`) |
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
│  Perplexity  Human    Coder       Reviewer  Tester   Human          │
│  (создаёт)  (одобр.) (кодирует)  (ревьюит) (тестир.) (закрывает)   │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
    VPS Contabo (164.68.116.250)
    ├── systemd: inside-coder.service    → pipeline/coder-daemon.sh
    ├── systemd: inside-reviewer.service → pipeline/reviewer-daemon.sh
    └── systemd: inside-tester.service  → pipeline/tester-daemon.sh
         │
         ▼
    Каждый агент:
    while true; do
        задача = найти_в_своей_колонке()
        if задача:
            обработать(задача)
            переместить_в_следующую_колонку()
        sleep 300
    done
```

---

## Описание колонок канбана

| Колонка | ID | Кто управляет | Действие |
|---------|-----|---------------|---------|
| **Backlog** | `f1d1f398` | Perplexity | Создаёт issue, ждёт одобрения |
| **To Do** | `5a8139d3` | Human | Одобрил задачу → Coder берёт |
| **In Progress** | `70b72213` | Coder | Активная разработка |
| **Review** | `2a164a07` | Reviewer | Code review + проверка спеки |
| **Testing** | `ba6f8676` | Tester | Спека-чеклист + тесты |
| **Done** | `6160c84d` | Human | Финальная проверка, закрытие |

---

## Ролевая матрица агентов

| Роль | Daemon | Берёт из | Двигает в | Gate |
|------|--------|----------|-----------|------|
| **Coder** | `coder-daemon.sh` | To Do | Review | Файлы изменены (`git status`) |
| **Reviewer** | `reviewer-daemon.sh` | Review | Testing / In Progress | Codex PASS |
| **Tester** | `tester-daemon.sh` | Testing | Done / In Progress | Codex PASS + тесты |

---

## Структура репозитория

```
inside/
├── .github/
│   ├── workflows/
│   │   └── ci.yml                  # Базовый CI (lint, test)
│   └── ISSUE_TEMPLATE/
│       └── task.md                 # Шаблон issue для задач
├── pipeline/
│   ├── common.sh                   # Общие функции: GraphQL API, логирование
│   ├── coder-daemon.sh             # Агент-программист (бесконечный цикл)
│   ├── reviewer-daemon.sh          # Агент-ревьюер (бесконечный цикл)
│   ├── tester-daemon.sh            # Агент-тестировщик (бесконечный цикл)
│   └── install.sh                  # Установщик на VPS
├── systemd/
│   ├── inside-coder.service         # Systemd unit для Coder
│   ├── inside-reviewer.service      # Systemd unit для Reviewer
│   └── inside-tester.service        # Systemd unit для Tester
├── src/                            # Исходный код продукта (заполняется агентами)
├── tests/                          # Тесты (заполняется агентами)
├── CODE.md                         # ← Этот файл (память проекта)
└── README.md                       # Пользовательская документация
```

---

## Конфигурация GitHub Projects

```
Project ID:     PVT_kwHOD_OjOs4BTTC0
Status Field:   PVTSSF_lAHOD_OjOs4BTTC0zhAlFI0
Repo:           ppxtestarena4/inside
```

Все ID задаются в `pipeline/common.sh` в массиве `COLUMN_IDS`.

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
# Статус агентов
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

# Остановить всё
systemctl stop inside-coder inside-reviewer inside-tester
```

---

## Клонирование для нового проекта

### 1. Склонировать шаблон

```bash
git clone https://github.com/ppxtestarena4/inside.git my-new-project
cd my-new-project

# Обновить origin на новый репозиторий
git remote set-url origin https://github.com/YOUR_ORG/YOUR_REPO.git
git push -u origin main
```

### 2. Создать GitHub Project

1. Создай новый **GitHub Projects v2** для репозитория
2. Добавь колонки: `Backlog`, `To Do`, `In Progress`, `Review`, `Testing`, `Done`
3. Запиши Project ID и Field ID (через GraphQL API или UI)

```bash
# Получить ID проекта
gh api graphql -f query='{ viewer { projectsV2(first: 10) { nodes { id title } } } }'
```

### 3. Обновить конфигурацию

В файле `pipeline/common.sh` замени:

```bash
PIPELINE_REPO="YOUR_ORG/YOUR_REPO"
PROJECT_ID="YOUR_PROJECT_ID"
STATUS_FIELD_ID="YOUR_STATUS_FIELD_ID"
COLUMN_IDS=(...)  # Замени все option IDs
```

### 4. Запустить установщик на VPS

```bash
ssh agent@YOUR_VPS_IP
git clone https://github.com/YOUR_ORG/YOUR_REPO.git
cd YOUR_REPO
sudo bash pipeline/install.sh
```

### 5. Обновить CODE.md

Обнови этот файл для нового проекта: описание, стек, VPS-данные.

---

## Защитные механизмы

1. **Блокировка задачи** — агент назначает issue на себя (`assignee`), другие агенты пропускают назначенные задачи
2. **Таймаут codex** — 30 мин для Coder, 15 мин для Reviewer и Tester
3. **Gate-проверки** — Coder: `git status --porcelain` не пуст; Reviewer/Tester: `VERDICT: PASS` в выводе Codex
4. **Fallback при ошибке** — любая ошибка → лог + комментарий в issue + задача остаётся в колонке
5. **Логирование** — все действия в `/var/log/inside/<daemon>.log` и systemd journal

---

## Соглашения о коде

- Все bash-скрипты начинаются с `set -euo pipefail`
- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`
- Ссылки на issue в коммитах: `Refs: #N`
- Комментарии в коде — английские, документация — русская
- Логи пишутся через функцию `log()` из `common.sh`

---

*Последнее обновление: 2026-03-31*
