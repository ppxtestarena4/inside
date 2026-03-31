# Inside

Автономный конвейер разработки на основе трёх агентов и GitHub Projects.

---

## Что это такое

**Inside** — готовая инфраструктура для автоматической разработки программного обеспечения:

- **Perplexity** (или человек) создаёт задачи в GitHub Issues с детальными спецификациями
- **Три агента** на VPS выполняют задачи автоматически, без участия человека:
  - `Coder` — берёт задачу, реализует код, пушит в ветку
  - `Reviewer` — проверяет код на соответствие спецификации
  - `Tester` — проверяет по чеклисту, запускает тесты, создаёт PR
- Вся координация через **GitHub Projects v2** (канбан: Backlog → To Do → In Progress → Review → Testing → Done)
- Агенты работают **непрерывно** как systemd-сервисы — перезапускаются автоматически после ребута

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Projects (канбан)                       │
│                                                                   │
│  Backlog ──► To Do ──► In Progress ──► Review ──► Testing ──► Done
│     │           │                                              │  │
│  Perplexity   Human                                         Tester│
│  создаёт      одобряет                                   создаёт PR
│                                                                   │
└────────────────────────────┬──────────────────────────────────────┘
                             │
                    VPS (systemd)
                    ├── inside-coder.service
                    │     └─ coder-daemon.sh (опрос каждые 5 мин)
                    │         To Do → [codex exec] → Review
                    │
                    ├── inside-reviewer.service
                    │     └─ reviewer-daemon.sh (опрос каждые 5 мин)
                    │         Review → [codex exec] → Testing / In Progress
                    │
                    └── inside-tester.service
                          └─ tester-daemon.sh (опрос каждые 5 мин)
                              Testing → [codex exec] → Done / In Progress
```

---

## Быстрый старт

### 1. Развернуть на VPS

```bash
ssh agent@164.68.116.250

# Клонировать репозиторий
git clone https://github.com/ppxtestarena4/inside.git
cd inside

# Установить агентов
sudo bash pipeline/install.sh
```

Установщик:
- Создаёт `/var/log/inside/`
- Копирует systemd unit-файлы в `/etc/systemd/system/`
- Запрашивает `OPENAI_API_KEY` и `PIPELINE_REPO`
- Включает и запускает все три сервиса

---

## Как добавлять задачи

1. Открой репозиторий на GitHub → **Issues** → **New Issue**
2. Выбери шаблон **«BRD / Спецификация Inside»**
3. Заполни спецификацию:
   - **Описание** — что нужно сделать (1-2 предложения)
   - **Спецификация** — детальные требования к реализации
   - **Файлы** — чеклист файлов для создания/изменения
   - **Критерии готовности** — по чему Tester поймёт, что всё сделано
4. Добавь issue в GitHub Project в колонку **Backlog**
5. После проверки переведи в **To Do** — Coder подхватит автоматически

### Пример хорошей спецификации

```markdown
## Описание
Добавить эндпоинт /api/users, возвращающий список пользователей.

## Спецификация
- GET /api/users → JSON массив [{id, name, email}]
- Лимит 100 записей, поддержка ?page=N
- Обработка ошибок: 500 с сообщением при сбое БД

## Файлы
- [ ] `src/routes/users.py` — роутер
- [ ] `tests/test_users.py` — тесты

## Критерии готовности
- [ ] Эндпоинт возвращает корректный JSON
- [ ] Пагинация работает
- [ ] Тест покрывает happy path и ошибку
```

---

## Мониторинг агентов

### Статус сервисов

```bash
systemctl status inside-coder inside-reviewer inside-tester
```

### Логи в реальном времени

```bash
# Через journalctl
journalctl -u inside-coder -f
journalctl -u inside-reviewer -f
journalctl -u inside-tester -f

# Через файлы
tail -f /var/log/inside/coder.log
tail -f /var/log/inside/reviewer.log
tail -f /var/log/inside/tester.log
```

### Управление

```bash
# Перезапустить агента
systemctl restart inside-coder

# Остановить всех
systemctl stop inside-coder inside-reviewer inside-tester

# Запустить всех
systemctl start inside-coder inside-reviewer inside-tester
```

---

## Канбан-доска

[Inside — Development Pipeline](https://github.com/users/ppxtestarena4/projects/3)

6 колонок: **Backlog** → **To Do** → **In Progress** → **Review** → **Testing** → **Done**

---

## Изоляция от Bravo

Оба проекта на одной VPS, но полностью изолированы:
- Разные репозитории, разные GitHub Projects
- Разные systemd-сервисы (`inside-*` vs `bravo-*`)
- Разные логи (`/var/log/inside/` vs `/var/log/bravo/`)

---

## Требования

| Компонент | Версия |
|-----------|--------|
| VPS OS | Ubuntu 22.04+ / Debian 12+ |
| `gh` CLI | 2.x+ (авторизован через `gh auth login`) |
| `codex` CLI | последняя версия |
| `git` | 2.x+ |
| `systemd` | 249+ |
| Доступ | `OPENAI_API_KEY` для Codex |

---

## Структура файлов

```
inside/
├── pipeline/
│   ├── common.sh           # Общие функции и конфигурация
│   ├── coder-daemon.sh     # Агент-программист
│   ├── reviewer-daemon.sh  # Агент-ревьюер
│   ├── tester-daemon.sh    # Агент-тестировщик
│   └── install.sh          # Установщик
├── systemd/
│   ├── inside-coder.service
│   ├── inside-reviewer.service
│   └── inside-tester.service
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── task.md         # Шаблон задачи
│   └── workflows/
│       └── codex-review.yml
├── src/                    # Код проекта (заполняется агентами)
├── tests/                  # Тесты (заполняются агентами)
├── CODE.md                 # Архитектурная документация для агентов
└── README.md               # Этот файл
```

---

## Лицензия

MIT — используй и адаптируй свободно.
