#!/usr/bin/env bash
# coder-daemon.sh — Агент-программист (Coder) для проекта Inside
#
# Роль: Claude Code
# Берёт задачи из колонки "To Do" (одобренные Human)
# Реализует код по BRD/спеке, пушит в ветку, передаёт в Review (Codex QA)
#
# Запускается через systemd (inside-coder.service)

set -euo pipefail

DAEMON_NAME="coder"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загружаем общие функции
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Константы
# ---------------------------------------------------------------------------

SLEEP_INTERVAL="${SLEEP_INTERVAL:-300}"   # 5 минут между итерациями
CLAUDE_TIMEOUT=1800                        # 30 минут максимум на claude

# ---------------------------------------------------------------------------
# Основная логика итерации
# ---------------------------------------------------------------------------

process_task() {
    local item_id="$1"
    local issue_number="$2"

    log "=== Начало обработки issue #${issue_number} (item: ${item_id}) ==="

    # 1. Назначить issue на себя (предотвращаем двойной захват)
    assign_issue "${issue_number}"

    # 2. Переместить в "In Progress"
    move_issue_to_status "${item_id}" "In Progress"
    log "Issue #${issue_number} → In Progress"

    # 3. Получить BRD/спецификацию из тела issue
    local issue_spec
    issue_spec=$(get_issue_body "${issue_number}")
    log "BRD/спецификация получена (${#issue_spec} символов)"

    # 4. Создать/переключиться на feature-ветку
    local branch_name="feature/issue-${issue_number}"
    cd "${REPO_DIR:-$(git rev-parse --show-toplevel)}"

    git checkout main --quiet
    git pull origin main --quiet

    if git ls-remote --exit-code --heads origin "${branch_name}" > /dev/null 2>&1; then
        git checkout "${branch_name}" --quiet
        git pull origin "${branch_name}" --quiet
    else
        git checkout -b "${branch_name}" --quiet
    fi

    log "Ветка ${branch_name} готова"

    # 5. Запустить Claude Code для реализации
    local claude_prompt
    claude_prompt=$(cat <<PROMPT
Ты — опытный разработчик проекта Inside. Прочитай файл CODE.md в этом репозитории для понимания проекта.

Затем реализуй следующую задачу из GitHub Issue #${issue_number}.
Это BRD (Business Requirements Document) / спецификация, написанная аналитиком:

${issue_spec}

Инструкции:
- Создай или измени все файлы, указанные в спецификации
- Следуй архитектуре, описанной в CODE.md
- Пиши чистый, хорошо документированный код
- Убедись, что все критерии приёмки из BRD выполнены
- Не создавай лишних файлов, не предусмотренных спецификацией
- Если есть тесты — убедись, что они проходят
PROMPT
)

    log "Запускаем Claude Code для issue #${issue_number}..."

    local claude_exit=0
    timeout "${CLAUDE_TIMEOUT}" claude --print "${claude_prompt}" || claude_exit=$?

    if [[ ${claude_exit} -eq 124 ]]; then
        log "ERROR: Claude превысил таймаут (${CLAUDE_TIMEOUT}s) для issue #${issue_number}"
        comment_on_issue "${issue_number}" "❌ **Coder (Claude)**: превышен таймаут выполнения (30 мин). Задача остаётся в In Progress."
        unassign_issue "${issue_number}"
        return 1
    elif [[ ${claude_exit} -ne 0 ]]; then
        log "ERROR: Claude завершился с кодом ${claude_exit} для issue #${issue_number}"
        comment_on_issue "${issue_number}" "❌ **Coder (Claude)**: ошибка выполнения (exit ${claude_exit}). Задача остаётся в In Progress."
        unassign_issue "${issue_number}"
        return 1
    fi

    # 6. Gate-проверка: должны быть изменения в файлах
    local git_status
    git_status=$(git status --porcelain)

    if [[ -z "${git_status}" ]]; then
        log "GATE FAILED: нет изменённых файлов для issue #${issue_number}"
        comment_on_issue "${issue_number}" "⚠️ **Coder (Claude)**: gate не пройден — не создал/изменил ни одного файла. Задача остаётся в In Progress для повторной попытки."
        unassign_issue "${issue_number}"
        return 1
    fi

    log "Gate пройден. Изменённые файлы:"
    log "${git_status}"

    # 7. Зафиксировать и запушить изменения
    git add -A

    local commit_msg
    commit_msg=$(cat <<MSG
feat: implement issue #${issue_number}

Implements BRD from GitHub Issue #${issue_number}.
Auto-implemented by Claude Code (inside-coder).

Refs: #${issue_number}
MSG
)

    git commit -m "${commit_msg}"
    git push origin "${branch_name}"
    log "Изменения запушены в ${branch_name}"

    # 8. Переместить в Review → Codex QA подхватит
    move_issue_to_status "${item_id}" "Review"
    log "Issue #${issue_number} → Review"

    # 9. Оставить комментарий
    local changed_files
    changed_files=$(git diff --name-only HEAD~1 HEAD | sed 's/^/- /')
    comment_on_issue "${issue_number}" "✅ **Coder (Claude)**: реализация завершена. Ветка: \`${branch_name}\`

**Изменённые файлы:**
${changed_files}

Задача передана в **Review** → Codex QA."

    log "=== Issue #${issue_number} обработан → Review ==="
}

# ---------------------------------------------------------------------------
# Главный цикл
# ---------------------------------------------------------------------------

main() {
    check_dependencies
    log "============================================"
    log "Inside Coder (Claude Code) запущен"
    log "Репозиторий: ${PIPELINE_REPO}"
    log "Интервал опроса: ${SLEEP_INTERVAL}s"
    log "============================================"

    while true; do
        log "--- Новая итерация ---"

        local task_line=""
        task_line=$(get_first_unassigned_item_by_status "To Do" 2>/dev/null || true)

        if [[ -z "${task_line}" ]]; then
            log "Нет задач в 'To Do'. Ожидание ${SLEEP_INTERVAL}s..."
        else
            local item_id issue_number
            item_id=$(echo "${task_line}" | awk '{print $1}')
            issue_number=$(echo "${task_line}" | awk '{print $2}')

            log "Найдена задача: issue #${issue_number} (item: ${item_id})"

            if ! process_task "${item_id}" "${issue_number}"; then
                log "ERROR: Обработка issue #${issue_number} завершилась с ошибкой. Продолжаем цикл."
            fi
        fi

        log "Ожидание ${SLEEP_INTERVAL}s до следующей итерации..."
        sleep "${SLEEP_INTERVAL}"
    done
}

main "$@"
