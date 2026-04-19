#!/bin/bash

# ============================================================
# limits.sh — Глобальные постоянные лимиты ресурсов
# ============================================================

RED="\e[91m"
GREEN="\e[92m"
CYAN="\e[96m"
DIM="\e[2m"
NC="\e[0m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запусти скрипт с правами root: sudo bash limits.sh${NC}"
    exit 1
fi

NOFILE=65536
NPROC=32768
MARKER="# CUSTOM RESOURCE LIMITS"

echo -e "${CYAN}Настройка глобальных лимитов ресурсов...${NC}"
echo ""

# ============================================================
# 1. /etc/security/limits.conf
# Применяется к SSH-сессиям и PAM-логинам
# ============================================================
if grep -q "$MARKER" /etc/security/limits.conf 2>/dev/null; then
    sed -i "/$MARKER/,/# END CUSTOM RESOURCE LIMITS/d" /etc/security/limits.conf
fi

cat >> /etc/security/limits.conf << EOF
$MARKER
*    soft nofile $NOFILE
*    hard nofile $NOFILE
root soft nofile $NOFILE
root hard nofile $NOFILE
*    soft nproc  $NPROC
*    hard nproc  $NPROC
root soft nproc  $NPROC
root hard nproc  $NPROC
# END CUSTOM RESOURCE LIMITS
EOF
echo -e "${GREEN}✓ /etc/security/limits.conf обновлён.${NC}"

# ============================================================
# 2. pam_limits.so — активирует limits.conf при SSH-входе
# ============================================================
if ! grep -q "pam_limits.so" /etc/pam.d/common-session 2>/dev/null; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
    echo -e "${GREEN}✓ pam_limits.so добавлен в common-session.${NC}"
else
    echo -e "${DIM}✓ pam_limits.so уже есть.${NC}"
fi

# ============================================================
# 3. systemd — лимиты для всех сервисов (nginx, docker и т.д.)
# limits.conf не применяется к юнитам systemd!
# ============================================================
mkdir -p /etc/systemd/system.conf.d/
cat > /etc/systemd/system.conf.d/limits.conf << EOF
[Manager]
DefaultLimitNOFILE=$NOFILE
DefaultLimitNPROC=$NPROC
EOF
echo -e "${GREEN}✓ systemd DefaultLimitNOFILE=$NOFILE, DefaultLimitNPROC=$NPROC.${NC}"

# Применяем немедленно без перезагрузки
systemctl daemon-reexec
echo -e "${GREEN}✓ systemd daemon-reexec выполнен.${NC}"

# ============================================================
# 4. sysctl — максимум открытых файлов на уровне ядра
# Это глобальный потолок для всей системы
# ============================================================
SYSCTL_CONF="/etc/sysctl.d/99-limits.conf"
cat > "$SYSCTL_CONF" << EOF
# Максимум открытых файловых дескрипторов для всей системы
fs.file-max = 2097152
# Максимум inotify-вотчеров (нужно Docker, IDE, файловым системам)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1
echo -e "${GREEN}✓ sysctl: fs.file-max=2097152, inotify обновлён.${NC}"

# ============================================================
# Проверка текущего состояния
# ============================================================
echo ""
echo -e "${CYAN}Проверка применённых лимитов:${NC}"
echo -e "  ${DIM}sysctl fs.file-max:${NC}          $(sysctl -n fs.file-max)"
echo -e "  ${DIM}systemd DefaultLimitNOFILE:${NC}  $(systemctl show --property=DefaultLimitNOFILE | cut -d= -f2)"
echo -e "  ${DIM}Текущая сессия (nofile):${NC}     $(ulimit -n)"
echo -e "  ${DIM}Текущая сессия (nproc):${NC}      $(ulimit -u)"

echo ""
echo -e "${GREEN}Готово! Лимиты применены на трёх уровнях:${NC}"
echo -e "  ${DIM}1. /etc/security/limits.conf  → SSH-сессии (после входа)${NC}"
echo -e "  ${DIM}2. systemd system.conf.d/      → все сервисы (nginx, docker...)${NC}"
echo -e "  ${DIM}3. sysctl fs.file-max          → ядро, глобальный потолок${NC}"
echo ""
echo -e "${CYAN}Для применения к уже запущенным сервисам:${NC}"
echo -e "  systemctl restart nginx"
echo -e "  systemctl restart docker"