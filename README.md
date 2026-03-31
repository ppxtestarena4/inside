# Inside

Автономный конвейер разработки на основе Claude Code + Codex CLI и GitHub Projects.

---

## Что это такое

**Inside** — инфраструктура для автоматической разработки программного обеспечения, работающая параллельно с проектом Bravo на общей VPS:

- **Perplexity** создаёт задачи в GitHub Issues с детальными спецификациями
- **Три агента** на VPS выполняют задачи автоматически:
  - `Coder` (Claude Code) — берёт задачу, реализует код, пушит в ветку
  - `Reviewer` (Codex CLI) — проверяет код на соответствие спецификации
  - `Tester` (Codex CLI) — тестирует, создаёт PR
- Координация через **GitHub Projects v2** (канбан: Backlog → To Do → In Progress → Review → Testing → Done)
- Агенты работают **непрерывно** как systemd-сервисы

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Projects (канбан)                       │
│                                                                   │
│  Backlog ──► To Do ──► In Progress ──► Review ──► Testing ──► Done│
│     │           │                                              │  │
│  Perplexity   Human                                         Tester│
│  создаёт      одобряет                                   создаёт PR│
│                                                                   │
└────────────────────────────┬──────────────────────────────────────┘
                             │
                    VPS (systemd)
                    ├── inside-coder.service
                    │     └─ coder-daemon.sh (Claude Code, опрос 5 мин)
                    │         To Do → [claude --print] → Review
                    │
                    ├── inside-reviewer.service
                    │     └─ reviewer-daemon.sh (Codex CLI, опрос 5 мин)
                    │         Review → [codex exec] → Testing / In Progress
                    │
                    └── inside-tester.service
                          └─ tester-daemon.sh (Codex CLI, опрос 5 мин)
                              Testing → [codex exec] → Done / In Progress
```

---

## Изоляция от Bravo

| Параметр | Bravo | Inside |
|----------|-------|--------|
| systemd-сервисы | `bravo-*` | `inside-*` |
| Логи | `/var/log/bravo/` | `/var/log/inside/` |
| GitHub Project | #1 | #3 |
| Рабочая директория | `~/bravo/` | `~/inside/` |

Оба проекта используют одну VPS и одни инструменты, но не мешают друг другу.

---

## Развёртывание на VPS

```bash
ssh agent@164.68.116.250

# Клонировать
git clone https://github.com/ppxtestarena4/inside.git
cd inside

# Установить агентов
sudo bash pipeline/install.sh
```

Установщик:
- Создаёт `/var/log/inside/`
- Копирует systemd unit-файлы
- Запрашивает `OPENAI_API_KEY`
- Включает и запускает 3 сервиса

---

## Как добавлять задачи

1. Откройте [Issues](https://github.com/ppxtestarena4/inside/issues) → **New Issue**
2. Выберите шаблон **«Задача Inside»**
3. Заполните спецификацию (описание, файлы, критерии готовности)
4. Добавьте issue в [GitHub Project](https://github.com/users/ppxtestarena4/projects/3) в колонку **Backlog**
5. После проверки переведите в **To Do** — Coder подхватит автоматически

---

## Мониторинг агентов

```bash
# Статус
systemctl status inside-coder inside-reviewer inside-tester

# Логи
journalctl -u inside-coder -f
journalctl -u inside-reviewer -f
journalctl -u inside-tester -f

# Управление
systemctl restart inside-coder
systemctl stop inside-coder inside-reviewer inside-tester
systemctl start inside-coder inside-reviewer inside-tester
```

---

## Структура файлов

```
inside/
├── pipeline/
│   ├── common.sh           # Общие функции и конфигурация
│   ├── coder-daemon.sh     # Агент-программист (Claude Code)
│   ├── reviewer-daemon.sh  # Агент-ревьюер (Codex CLI)
│   ├── tester-daemon.sh    # Агент-тестировщик (Codex CLI)
│   └── install.sh          # Установщик
├── systemd/
│   ├── inside-coder.service
│   ├── inside-reviewer.service
│   └── inside-tester.service
├── .github/
│   └── ISSUE_TEMPLATE/
│       └── task.md         # Шаблон задачи
├── src/                    # Код проекта
├── tests/                  # Тесты
├── CODE.md                 # Архитектурная документация для агентов
└── README.md               # Этот файл
```

---

## Лицензия

MIT
