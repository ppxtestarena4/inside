# Inside

Автономный конвейер разработки с чётким разделением ролей.

---

## Роли

| Роль | Агент | Что делает |
|------|-------|-----------|
| **Аналитик** | Perplexity | Пишет BRD/спецификации → Backlog |
| **Human** | Вы | Проверяет спеку → To Do |
| **Кодер** | Claude Code | Реализует по BRD → Review |
| **QA** | Codex CLI | Ревью + тесты + BRD-check → Done / To Do |

---

## Поток

```
Perplexity ──► Backlog ──► Human одобряет ──► To Do
                                                │
                              Claude Code ◄─────┘
                                   │
                              In Progress
                                   │
                              Review (Codex QA)
                               ╱         ╲
                           PASS            FAIL
                            │                │
                          Done          To Do (повтор)
```

---

## Канбан-доска

[Inside — Development Pipeline](https://github.com/users/ppxtestarena4/projects/3)

5 колонок: **Backlog** → **To Do** → **In Progress** → **Review** → **Done**

---

## Развёртывание на VPS

```bash
ssh agent@164.68.116.250

git clone https://github.com/ppxtestarena4/inside.git
cd inside

sudo bash pipeline/install.sh
```

Установщик запускает 2 сервиса:
- `inside-coder` — Claude Code (берёт из To Do)
- `inside-qa` — Codex CLI (берёт из Review)

---

## Как добавлять задачи

1. Откройте [Issues](https://github.com/ppxtestarena4/inside/issues) → **New Issue**
2. Выберите шаблон **«BRD / Спецификация Inside»**
3. Заполните BRD: описание, спецификацию, файлы, критерии приёмки
4. Добавьте в [канбан](https://github.com/users/ppxtestarena4/projects/3) → **Backlog**
5. Human проверяет и двигает в **To Do** → Claude подхватит

---

## Мониторинг

```bash
systemctl status inside-coder inside-qa

journalctl -u inside-coder -f
journalctl -u inside-qa -f

# Остановить (не затронет Bravo)
systemctl stop inside-coder inside-qa
```

---

## Изоляция от Bravo

Оба проекта на одной VPS, но полностью изолированы:
- Разные репозитории, разные GitHub Projects
- Разные systemd-сервисы (`inside-*` vs `bravo-*`)
- Разные логи (`/var/log/inside/` vs `/var/log/bravo/`)

---

## Структура

```
inside/
├── pipeline/
│   ├── common.sh           # Конфигурация и общие функции
│   ├── coder-daemon.sh     # Claude Code (кодер)
│   ├── qa-daemon.sh        # Codex CLI (QA)
│   └── install.sh          # Установщик
├── systemd/
│   ├── inside-coder.service
│   └── inside-qa.service
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── task.md         # BRD-шаблон
│   └── workflows/
│       └── codex-review.yml
├── src/                    # Код
├── tests/                  # Тесты
├── CODE.md                 # Память проекта для агентов
└── README.md               # Этот файл
```
