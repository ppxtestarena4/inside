#!/usr/bin/env bash
# install.sh — Установка и настройка pipeline Inside на VPS
# Запускать от root или с sudo.
# Используется: sudo bash pipeline/install.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Константы
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="/var/log/inside"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_FILES=("inside-coder.service" "inside-qa.service")

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Этот скрипт должен быть запущен с правами root (sudo bash install.sh)"
    fi
}

check_deps() {
    info "Проверка зависимостей..."
    local missing=()

    for dep in gh git codex systemctl; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Отсутствуют: ${missing[*]}"
        read -r -p "Продолжить без них? [y/N]: " continue_anyway
        [[ "${continue_anyway}" =~ ^[Yy]$ ]] || die "Установка отменена."
    else
        success "Все зависимости найдены"
    fi
}

setup_log_dir() {
    info "Создание директории логов: ${LOG_DIR}"
    mkdir -p "${LOG_DIR}"
    chown -R agent:agent "${LOG_DIR}" 2>/dev/null || {
        warn "Пользователь 'agent' не найден."
    }
    chmod 755 "${LOG_DIR}"
    success "Директория ${LOG_DIR} создана"
}

collect_config() {
    echo ""
    echo "========================================"
    echo " Настройка Inside Pipeline"
    echo " 2 агента: Coder (Claude) + QA (Codex)"
    echo "========================================"
    echo ""

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        info "OPENAI_API_KEY уже задан в окружении"
        CONFIGURED_API_KEY="${OPENAI_API_KEY}"
    else
        read -r -s -p "Введите OPENAI_API_KEY (для Codex QA): " CONFIGURED_API_KEY
        echo ""
        [[ -z "${CONFIGURED_API_KEY}" ]] && die "OPENAI_API_KEY не может быть пустым"
    fi

    local default_repo="ppxtestarena4/inside"
    read -r -p "Введите PIPELINE_REPO [${default_repo}]: " CONFIGURED_REPO
    CONFIGURED_REPO="${CONFIGURED_REPO:-${default_repo}}"

    echo ""
    info "Конфигурация:"
    info "  PIPELINE_REPO: ${CONFIGURED_REPO}"
    info "  OPENAI_API_KEY: ${CONFIGURED_API_KEY:0:8}..."
    echo ""
    read -r -p "Подтвердить? [y/N]: " confirm
    [[ "${confirm}" =~ ^[Yy]$ ]] || die "Установка отменена."
}

install_systemd_units() {
    info "Копирование systemd unit-файлов..."

    local systemd_source="${REPO_DIR}/systemd"

    if [[ ! -d "${systemd_source}" ]]; then
        die "Директория ${systemd_source} не найдена"
    fi

    for service in "${SERVICE_FILES[@]}"; do
        local src="${systemd_source}/${service}"
        local dst="${SYSTEMD_DIR}/${service}"

        if [[ ! -f "${src}" ]]; then
            error "Файл ${src} не найден"
            continue
        fi

        sed \
            -e "s|/home/agent/<repo>|${REPO_DIR}|g" \
            -e "s|OPENAI_API_KEY=|OPENAI_API_KEY=${CONFIGURED_API_KEY}|" \
            -e "s|PIPELINE_REPO=ppxtestarena4/inside|PIPELINE_REPO=${CONFIGURED_REPO}|" \
            "${src}" > "${dst}"

        chmod 644 "${dst}"
        success "Установлен: ${dst}"
    done

    # Удалить устаревшие сервисы (reviewer/tester) если были
    for old_service in inside-reviewer.service inside-tester.service; do
        if [[ -f "${SYSTEMD_DIR}/${old_service}" ]]; then
            systemctl stop "${old_service}" 2>/dev/null || true
            systemctl disable "${old_service}" 2>/dev/null || true
            rm -f "${SYSTEMD_DIR}/${old_service}"
            info "Удалён устаревший: ${old_service}"
        fi
    done

    systemctl daemon-reload
    success "systemd daemon перезагружен"
}

enable_and_start_services() {
    info "Включение и запуск сервисов..."

    for service in "${SERVICE_FILES[@]}"; do
        local service_name="${service%.service}"
        systemctl enable "${service}" 2>/dev/null || warn "Не удалось включить ${service}"
        systemctl start "${service}" 2>/dev/null || warn "Не удалось запустить ${service}"
        success "Сервис ${service_name} запущен"
    done
}

show_status() {
    echo ""
    echo "========================================"
    echo " Статус сервисов Inside Pipeline"
    echo "========================================"
    echo ""

    for service in "${SERVICE_FILES[@]}"; do
        local status
        status=$(systemctl is-active "${service}" 2>/dev/null || echo "неизвестно")
        local color="${GREEN}"
        [[ "${status}" != "active" ]] && color="${RED}"
        echo -e "  ${color}${service}${NC}: ${status}"
    done

    echo ""
    info "Логи: journalctl -u inside-coder -f / journalctl -u inside-qa -f"
    info "Остановить: systemctl stop inside-coder inside-qa"
    echo ""
    success "Установка завершена!"
}

main() {
    echo ""
    echo "  ██ ███    ██ ███████ ██ ██████  ███████ "
    echo "  ██ ████   ██ ██      ██ ██   ██ ██      "
    echo "  ██ ██ ██  ██ ███████ ██ ██   ██ █████   "
    echo "  ██ ██  ██ ██      ██ ██ ██   ██ ██      "
    echo "  ██ ██   ████ ███████ ██ ██████  ███████ "
    echo ""
    echo "  2 агента: Claude Code (Coder) + Codex CLI (QA)"
    echo ""

    check_root
    check_deps
    collect_config
    setup_log_dir
    install_systemd_units
    enable_and_start_services
    show_status
}

main "$@"
