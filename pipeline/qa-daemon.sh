#!/usr/bin/env bash
# qa-daemon.sh — Единый агент QA (Reviewer + Tester) для проекта Inside
#
# Роль: Codex CLI
# Берёт задачи из колонки "Review"
# Выполняет:
#   1. Code review — соответствие кода спецификации/BRD
#   2. Тестирование — запуск тестов, проверка чеклиста
#   3. QA-вердикт — PASS → Done (+ PR), FAIL → To Do (на доработку Claude)
#
# Запускается через systemd (inside-qa.service)

set -euo pipefail

DAEMON_NAME="qa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загружаем общие функции
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Константы
# ---------------------------------------------------------------------------

SLEEP_INTERVAL="${SLEEP_INTERVAL:-300}"   # 5 минут между итерациями
CODEX_TIMEOUT=900                          # 15 минут максимум на QA

# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------

# create_pull_request <branch_name> <issue_number>
create_pull_request() {
    local branch_name="$1"
    local issue_number="$2"

    local issue_title
    issue_title=$(gh api "repos/${PIPELINE_REPO}/issues/${issue_number}" --jq '.title')

    local pr_body
    pr_body=$(cat <<BODY
## Описание

Автоматически созданный Pull Request после прохождения конвейера Inside.

**Реализует:** #${issue_number} — ${issue_title}

## Чеклист конвейера

- [x] **Perplexity** (аналитик): BRD/спека создана
- [x] **Human**: спека одобрена
- [x] **Claude Code** (кодер): реализация завершена
- [x] **Codex CLI** (QA): ревью + тесты + проверка по BRD пройдены

Closes #${issue_number}
BODY
)

    local pr_url
    pr_url=$(gh pr create \
        --repo "${PIPELINE_REPO}" \
        --base main \
        --head "${branch_name}" \
        --title "feat: ${issue_title} (#${issue_number})" \
        --body "${pr_body}" \
        2>&1) || {
        log "WARN: PR уже существует или ошибка создания: ${pr_url}"
        pr_url=$(gh pr list --repo "${PIPELINE_REPO}" --head "${branch_name}" --json url --jq '.[0].url' 2>/dev/null || echo "не определён")
    }

    echo "${pr_url}"
}

# ---------------------------------------------------------------------------
# Основная логика
# ---------------------------------------------------------------------------

process_qa() {
    local item_id="$1"
    local issue_number="$2"

    log "=== Начало QA для issue #${issue_number} (item: ${item_id}) ==="

    # 1. Назначить issue на себя
    assign_issue "${issue_number}"

    # 2. Получить BRD/спецификацию
    local issue_spec
    issue_spec=$(get_issue_body "${issue_number}")
    log "BRD/спецификация получена (${#issue_spec} символов)"

    # 3. Переключиться на feature-ветку
    local branch_name="feature/issue-${issue_number}"
    cd "${REPO_DIR:-$(git rev-parse --show-toplevel)}"

    git fetch origin --quiet

    if ! git ls-remote --exit-code --heads origin "${branch_name}" > /dev/null 2>&1; then
        log "ERROR: Ветка ${branch_name} не найдена в origin"
        comment_on_issue "${issue_number}" "❌ **QA (Codex)**: ветка \`${branch_name}\` не найдена. Возвращаем в To Do."
        move_issue_to_status "${item_id}" "To Do"
        unassign_issue "${issue_number}"
        return 1
    fi

    git checkout "${branch_name}" --quiet
    git pull origin "${branch_name}" --quiet

    # 4. Получить изменённые файлы
    local changed_files
    changed_files=$(git diff --name-only "origin/main...HEAD" 2>/dev/null || git diff --name-only HEAD~1 HEAD)

    if [[ -z "${changed_files}" ]]; then
        log "ERROR: Нет изменённых файлов в ветке ${branch_name}"
        comment_on_issue "${issue_number}" "❌ **QA (Codex)**: нет изменений в ветке. Возвращаем в To Do."
        move_issue_to_status "${item_id}" "To Do"
        unassign_issue "${issue_number}"
        return 1
    fi

    log "Изменённые файлы: ${changed_files}"

    # Собираем содержимое файлов
    local files_content=""
    while IFS= read -r file; do
        if [[ -f "${file}" ]]; then
            files_content+=$'\n\n'"=== Файл: ${file} ==="$'\n'
            files_content+=$(cat "${file}")
        fi
    done <<< "${changed_files}"

    # 5. Запустить реальные тесты (если есть)
    local test_results="Автоматические тесты не обнаружены в репозитории."

    if [[ -f "tests/run_tests.sh" ]]; then
        log "Найден tests/run_tests.sh, запускаем..."
        test_results=$(bash tests/run_tests.sh 2>&1) || {
            log "Тесты завершились с ошибкой"
            test_results="ОШИБКА ЗАПУСКА ТЕСТОВ:\n${test_results}"
        }
    elif [[ -f "pytest.ini" ]] || [[ -f "setup.cfg" ]] || find . -name "test_*.py" -maxdepth 3 | grep -q .; then
        log "Найдены pytest-тесты, запускаем..."
        test_results=$(python -m pytest --tb=short 2>&1) || {
            log "pytest завершился с ошибкой"
        }
    elif find . -name "*.test.js" -maxdepth 4 | grep -q . || [[ -f "package.json" ]]; then
        if command -v npm &>/dev/null && grep -q '"test"' package.json 2>/dev/null; then
            log "Найдены npm-тесты, запускаем..."
            test_results=$(npm test 2>&1) || {
                log "npm test завершился с ошибкой"
            }
        fi
    fi

    # 6. Codex QA — единый проход: ревью + тесты + соответствие BRD
    local codex_prompt
    codex_prompt=$(cat <<PROMPT
Ты — QA-инженер проекта Inside. Проведи полную проверку реализации.

## BRD / Спецификация задачи (Issue #${issue_number})

${issue_spec}

## Реализованный код

${files_content}

## Результаты автоматических тестов

${test_results}

## Задача QA (всё в одном проходе)

### 1. Code Review
- Соответствует ли код спецификации/BRD?
- Качество кода: читаемость, структура, отсутствие дублирования
- Безопасность: нет ли уязвимостей, открытых секретов?
- Обработка ошибок корректна?

### 2. Тестирование
- Все критерии приёмки из BRD выполнены?
- Все файлы из чеклиста существуют?
- Автоматические тесты прошли (если были)?
- Граничные случаи обработаны?

### 3. Соответствие BRD
- Каждый пункт BRD реализован?
- Нет ли отклонений от спецификации?
- Все acceptance criteria удовлетворены?

## Формат ответа

Дай подробный отчёт по каждому разделу. В ПОСЛЕДНЕЙ строке напиши ТОЛЬКО одно:
VERDICT: PASS
VERDICT: FAIL

При FAIL обязательно укажи конкретные проблемы и что нужно исправить.
PROMPT
)

    log "Запускаем Codex QA для issue #${issue_number}..."

    local qa_output=""
    local codex_exit=0

    qa_output=$(timeout "${CODEX_TIMEOUT}" codex exec --full-auto "${codex_prompt}" 2>&1) || codex_exit=$?

    if [[ ${codex_exit} -eq 124 ]]; then
        log "ERROR: Codex превысил таймаут для QA issue #${issue_number}"
        comment_on_issue "${issue_number}" "❌ **QA (Codex)**: превышен таймаут (15 мин). Возвращаем в To Do."
        move_issue_to_status "${item_id}" "To Do"
        unassign_issue "${issue_number}"
        return 1
    elif [[ ${codex_exit} -ne 0 ]]; then
        log "ERROR: Codex завершился с кодом ${codex_exit}"
        comment_on_issue "${issue_number}" "❌ **QA (Codex)**: ошибка выполнения (exit ${codex_exit}). Возвращаем в To Do."
        move_issue_to_status "${item_id}" "To Do"
        unassign_issue "${issue_number}"
        return 1
    fi

    log "Codex QA завершён. Анализируем вердикт..."

    # 7. Парсим вердикт
    local verdict=""
    verdict=$(echo "${qa_output}" | grep -o 'VERDICT: \(PASS\|FAIL\)' | tail -n 1 | awk '{print $2}')

    if [[ -z "${verdict}" ]]; then
        log "WARN: Вердикт не найден в выводе Codex. Считаем FAIL."
        verdict="FAIL"
    fi

    log "Вердикт QA для issue #${issue_number}: ${verdict}"

    # 8. Действие по вердикту
    if [[ "${verdict}" == "PASS" ]]; then
        # → Done + создать PR
        move_issue_to_status "${item_id}" "Done"
        log "Issue #${issue_number} → Done"

        local pr_url
        pr_url=$(create_pull_request "${branch_name}" "${issue_number}")
        log "Pull Request создан: ${pr_url}"

        comment_on_issue "${issue_number}" "✅ **QA (Codex)**: все проверки пройдены!

**Отчёт QA:**
${qa_output}

**Pull Request:** ${pr_url}

Задача перемещена в **Done**. Ожидается merge."

        log "=== Issue #${issue_number} → Done ==="

    else
        # FAIL → возврат в To Do (Claude подхватит снова)
        move_issue_to_status "${item_id}" "To Do"
        log "Issue #${issue_number} → To Do (QA не пройдено)"

        comment_on_issue "${issue_number}" "🔄 **QA (Codex)**: проверка не пройдена. Требуются исправления.

**Отчёт QA:**
${qa_output}

Задача возвращена в **To Do** — Claude Code подхватит для доработки."

        log "=== Issue #${issue_number} не прошёл QA → To Do ==="
    fi

    unassign_issue "${issue_number}"
}

# ---------------------------------------------------------------------------
# Главный цикл
# ---------------------------------------------------------------------------

main() {
    check_dependencies
    log "============================================"
    log "Inside QA (Codex CLI) запущен"
    log "Репозиторий: ${PIPELINE_REPO}"
    log "Интервал опроса: ${SLEEP_INTERVAL}s"
    log "============================================"

    while true; do
        log "--- Новая итерация ---"

        local task_line=""
        task_line=$(get_first_unassigned_item_by_status "Review" 2>/dev/null || true)

        if [[ -z "${task_line}" ]]; then
            log "Нет задач в 'Review'. Ожидание ${SLEEP_INTERVAL}s..."
        else
            local item_id issue_number
            item_id=$(echo "${task_line}" | awk '{print $1}')
            issue_number=$(echo "${task_line}" | awk '{print $2}')

            log "Найдена задача для QA: issue #${issue_number} (item: ${item_id})"

            if ! process_qa "${item_id}" "${issue_number}"; then
                log "ERROR: QA issue #${issue_number} завершилось с ошибкой. Продолжаем цикл."
            fi
        fi

        log "Ожидание ${SLEEP_INTERVAL}s до следующей итерации..."
        sleep "${SLEEP_INTERVAL}"
    done
}

main "$@"
