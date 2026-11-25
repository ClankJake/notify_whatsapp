#!/usr/bin/env bash
#
# Instalador / atualizador do go-whatsapp-web-multidevice como serviço systemd.
#
# Uso: sudo ./install_go-whatsapp.sh [opções]   (veja --help)

set -Eeuo pipefail

# --- VARIÁVEIS FIXAS ---------------------------------------------------------
REPO="aldinokemal/go-whatsapp-web-multidevice"
LATEST_REDIRECT_URL="https://github.com/${REPO}/releases/latest"
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"

SERVICE_NAME="go-whatsapp-web"
BIN_PATH="/usr/local/bin/go-whatsapp-web"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/${SERVICE_NAME}.env"
WORK_DIR="/var/lib/go-whatsapp-web"
VERSION_FILE="/usr/local/bin/go-whatsapp-web.version"

DEFAULT_SERVICE_USER="gowa"
KEEP_BACKUPS=3

# --- PARÂMETROS (padrões) ----------------------------------------------------
NO_INTERACTIVE=false
RESET_SERVICE=false
FORCE_UPDATE=false
UNINSTALL=false
PURGE=false
PORT="3000"
PORT_SET=false
AUTH="${GOWA_BASIC_AUTH:-}"          # formato usuario:senha
TRUSTED_PROXIES="0.0.0.0/0"
SERVICE_USER=""
SKIP_CHECKSUM=false

TMP_DIR=""
NEW_BIN=""
BACKUP_PATH=""

# --- LOG ---------------------------------------------------------------------
log()  { echo "[INFO] $*" >&2; }
warn() { echo "⚠️  $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  return 0
}
trap cleanup EXIT

usage() {
  cat <<EOF
Uso: $0 [opções]

  --no-interactive        Não faz perguntas (usa os valores abaixo ou os padrões)
  --port=PORTA            Porta do servidor (padrão: 3000)
  --basic-auth=USER:SENHA Habilita autenticação básica
                          (alternativa mais segura: exportar GOWA_BASIC_AUTH)
  --trusted-proxies=CIDR  Proxies confiáveis (padrão: 0.0.0.0/0)
  --user=NOME             Usuário que roda o serviço (padrão: o já configurado,
                          ou o usuário de sistema '${DEFAULT_SERVICE_USER}')
  --skip-checksum         Não verifica o SHA-256 do download (não recomendado)
  --reset-service         Recria o arquivo do serviço (mantém os dados/sessão)
  --force-update          Reinstala o binário mesmo se já estiver na última versão
  --uninstall             Remove binário e serviço (mantém a sessão)
  --purge                 Com --uninstall, apaga também $WORK_DIR (sessão!)
  -h, --help              Mostra esta ajuda
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-interactive)    NO_INTERACTIVE=true ;;
    --skip-checksum)     SKIP_CHECKSUM=true ;;
    --reset-service)     RESET_SERVICE=true ;;
    --force-update)      FORCE_UPDATE=true ;;
    --uninstall)         UNINSTALL=true ;;
    --purge)             PURGE=true ;;
    --port=*)            PORT="${arg#*=}"; PORT_SET=true ;;
    --basic-auth=*)      AUTH="${arg#*=}" ;;
    --trusted-proxies=*) TRUSTED_PROXIES="${arg#*=}" ;;
    --user=*)            SERVICE_USER="${arg#*=}" ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Opção inválida: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

# --- VERIFICAÇÕES INICIAIS ---------------------------------------------------
[[ $EUID -eq 0 ]] || die "Por favor, execute como root ou use sudo."

for cmd in curl unzip find install sed awk mktemp id useradd systemctl sha256sum; do
  command -v "$cmd" &>/dev/null \
    || die "O comando '$cmd' é necessário, mas não foi encontrado (ex: sudo apt install $cmd)."
done

case "$(uname -m)" in
  x86_64)          BIN_ARCH="amd64" ;;
  aarch64|arm64)   BIN_ARCH="arm64" ;;
  armv7l|armv7)    BIN_ARCH="armv7" ;;
  i386|i686)       BIN_ARCH="386" ;;
  *) die "Arquitetura $(uname -m) não suportada." ;;
esac

# --- FUNÇÕES AUXILIARES ------------------------------------------------------

# Existe um terminal para perguntas? (falha em `curl | bash` sem tty)
have_tty() { { : </dev/tty; } 2>/dev/null; }

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )) \
    || die "Porta inválida: '$1' (use um número entre 1 e 65535)."
}

validate_auth() {
  [[ "$1" == ?*:?* ]] || die "Autenticação deve estar no formato usuario:senha."
  case "$1" in
    *\'*|*\"*|*\\*|*,*|*$'\n'*)
      die "Usuário/senha não podem conter aspas, barra invertida, vírgula ou quebra de linha."
      ;;
  esac
}

# Descobre a tag mais recente seguindo o redirect de /releases/latest
get_latest_tag() {
  local final_url tag
  log "Buscando a versão mais recente no GitHub..."
  final_url=$(curl -fsSL --retry 3 --connect-timeout 10 \
    -o /dev/null -w '%{url_effective}' "$LATEST_REDIRECT_URL") \
    || die "Não foi possível acessar o GitHub."
  [[ "$final_url" == */tag/* ]] || die "Não foi possível obter a versão mais recente."
  tag="${final_url##*/tag/}"
  [[ -n "$tag" ]] || die "Tag da versão mais recente vazia."
  printf '%s\n' "$tag"
}

# Confere o SHA-256 do ZIP baixado contra o checksums.txt do release
verify_checksum() {
  local tag="$1" filename="$2" sums_url expected actual
  if [[ "$SKIP_CHECKSUM" = true ]]; then
    warn "Verificação de checksum desativada (--skip-checksum)."
    return 0
  fi

  sums_url="${DOWNLOAD_BASE}/${tag}/checksums.txt"
  log "Verificando SHA-256..."
  curl -fsSL --retry 3 --connect-timeout 10 -o "$TMP_DIR/checksums.txt" "$sums_url" \
    || die "Não foi possível baixar $sums_url (use --skip-checksum para ignorar)."

  expected=$(awk -v f="$filename" '$2 == f || $2 == "*" f { print $1; exit }' "$TMP_DIR/checksums.txt")
  [[ -n "$expected" ]] || die "$filename não consta em checksums.txt."

  actual=$(sha256sum "$TMP_DIR/$filename" | awk '{ print $1 }')
  [[ "$actual" == "$expected" ]] \
    || die "Checksum inválido para $filename (esperado $expected, obtido $actual). Download descartado."
  log "✅ Checksum OK."
}

# Baixa e extrai o binário em um diretório temporário; define NEW_BIN
fetch_binary() {
  local tag="$1" version filename url
  version="${tag#v}"
  filename="whatsapp_${version}_linux_${BIN_ARCH}.zip"
  url="${DOWNLOAD_BASE}/${tag}/${filename}"

  TMP_DIR=$(mktemp -d)

  log "Baixando $url"
  curl -fL --retry 3 --connect-timeout 10 -# -o "$TMP_DIR/$filename" "$url" \
    || die "Falha ao baixar $url (a versão pode não ter binário para $BIN_ARCH)."

  verify_checksum "$tag" "$filename"

  log "Extraindo binário..."
  unzip -q -o "$TMP_DIR/$filename" -d "$TMP_DIR/extract" \
    || die "Falha ao extrair o ZIP."

  NEW_BIN=$(find "$TMP_DIR/extract" -type f \
    ! -iname '*.md' ! -iname '*.txt' ! -iname 'LICENSE*' | head -n 1)
  [[ -n "$NEW_BIN" ]] || die "Nenhum executável encontrado dentro do ZIP."

  # Sanidade: o arquivo precisa ser um ELF
  [[ "$(head -c 4 "$NEW_BIN" | tail -c 3)" == "ELF" ]] \
    || die "O arquivo extraído não parece um executável Linux (ELF)."

  log "Executável detectado: $(basename "$NEW_BIN")"
}

# Instala NEW_BIN em BIN_PATH de forma atômica, guardando backup do anterior
install_binary() {
  BACKUP_PATH=""
  if [[ -f "$BIN_PATH" ]]; then
    BACKUP_PATH="${BIN_PATH}.bak.$(date +%s)"
    cp -p "$BIN_PATH" "$BACKUP_PATH"
    log "🔙 Backup salvo: $BACKUP_PATH"
  fi
  install -m 755 "$NEW_BIN" "${BIN_PATH}.new"
  mv -f "${BIN_PATH}.new" "$BIN_PATH"
}

prune_backups() {
  # shellcheck disable=SC2012
  ls -1t "${BIN_PATH}".bak.* 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f || true
}

# Espera o serviço ficar ativo e estável por alguns segundos
wait_healthy() {
  local i
  for i in 1 2 3 4 5; do
    sleep 2
    systemctl is-active --quiet "${SERVICE_NAME}.service" || return 1
  done
  return 0
}

port_in_use() {
  command -v ss &>/dev/null || return 1
  ss -ltn "sport = :$1" 2>/dev/null | tail -n +2 | grep -q .
}

ensure_service_user() {
  if [[ -z "$SERVICE_USER" ]]; then
    if [[ -f "$SERVICE_PATH" ]]; then
      SERVICE_USER=$(sed -n 's/^User=//p' "$SERVICE_PATH" | head -n 1)
    fi
    SERVICE_USER="${SERVICE_USER:-$DEFAULT_SERVICE_USER}"
  fi

  if ! id "$SERVICE_USER" &>/dev/null; then
    log "Criando usuário de sistema '$SERVICE_USER'..."
    useradd --system --user-group --no-create-home \
      --home-dir "$WORK_DIR" \
      --shell "$(command -v nologin || echo /usr/sbin/nologin)" "$SERVICE_USER"
  fi
  SERVICE_GROUP=$(id -gn "$SERVICE_USER")
}

prepare_work_dir() {
  mkdir -p "$WORK_DIR"
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$WORK_DIR"
  chmod 700 "$WORK_DIR"
}

# Escreve o env file (só se houver senha) e o unit do systemd
write_service() {
  local exec_start unit_env=""

  exec_start="$BIN_PATH rest --port=${PORT} --os=Chrome --account-validation=false"
  exec_start+=" --trusted-proxies=${TRUSTED_PROXIES} --auto-download-media=false"

  if [[ -n "$AUTH" ]]; then
    # A senha fica em arquivo 600 (root), fora do unit (que é legível por todos)
    # e fora da linha de comando visível em `ps`.
    umask 077
    printf 'GOWA_BASIC_AUTH="%s"\n' "$AUTH" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    umask 022
    unit_env="EnvironmentFile=${ENV_FILE}"
    exec_start+=' --basic-auth=${GOWA_BASIC_AUTH}'
  else
    rm -f "$ENV_FILE"
  fi

  log "Criando arquivo systemd..."
  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Go WhatsApp Web Multi-Device
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${exec_start}
${unit_env}
Restart=on-failure
RestartSec=5
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${WORK_DIR}
StandardOutput=journal
StandardError=journal

# Hardening (se algo deixar de funcionar, comente estas linhas para testar)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${WORK_DIR}

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$SERVICE_PATH"
}

# --- DESINSTALAÇÃO -----------------------------------------------------------
do_uninstall() {
  log "Removendo serviço e binário..."
  systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
  rm -f "$SERVICE_PATH" "$ENV_FILE" "$BIN_PATH" "$VERSION_FILE" "${BIN_PATH}".bak.*
  systemctl daemon-reload
  if [[ "$PURGE" = true ]]; then
    rm -rf "$WORK_DIR"
    log "🗑️  $WORK_DIR removido (sessão do WhatsApp apagada)."
  else
    log "Dados mantidos em $WORK_DIR (use --purge para apagar)."
  fi
  log "✅ Desinstalado."
}

# --- ATUALIZAÇÃO -------------------------------------------------------------
do_update() {
  local latest installed="none"

  [[ "$FORCE_UPDATE" = true ]] \
    && log "⚠️  Forçando a reinstalação da versão mais recente..." \
    || log "Serviço já existente detectado. Verificando versão..."

  latest=$(get_latest_tag)
  if [[ -f "$VERSION_FILE" ]]; then
    installed=$(<"$VERSION_FILE")
  fi

  if [[ "$installed" == "$latest" && "$FORCE_UPDATE" = false ]]; then
    log "✅ Já está na versão mais recente: $installed"
    log "   (Use --force-update para reinstalar a mesma versão)"
    return 0
  fi

  log "📦 Atualizando de $installed para $latest..."

  # Baixa ANTES de parar o serviço: se falhar, nada fica fora do ar
  fetch_binary "$latest"

  systemctl stop "${SERVICE_NAME}.service"
  install_binary
  echo "$latest" > "$VERSION_FILE"
  systemctl daemon-reload
  systemctl start "${SERVICE_NAME}.service"

  if wait_healthy; then
    prune_backups
    log "✅ Atualizado para a versão $latest"
    return 0
  fi

  warn "O serviço não subiu com a nova versão."
  if [[ -n "$BACKUP_PATH" && -f "$BACKUP_PATH" ]]; then
    warn "Restaurando backup $BACKUP_PATH..."
    systemctl stop "${SERVICE_NAME}.service" || true
    install -m 755 "$BACKUP_PATH" "$BIN_PATH"
    [[ "$installed" != "none" ]] && echo "$installed" > "$VERSION_FILE"
    systemctl start "${SERVICE_NAME}.service" || true
  fi
  die "Atualização falhou. Veja: journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
}

# --- PRIMEIRA INSTALAÇÃO / RESET --------------------------------------------
do_install() {
  local latest answer pass1 pass2 user

  if [[ "$NO_INTERACTIVE" = false ]] && have_tty; then
    if [[ "$PORT_SET" = false ]]; then
      read -r -p "Digite a porta para o servidor (padrão: 3000): " answer </dev/tty
      PORT="${answer:-3000}"
    fi

    if [[ -z "$AUTH" ]]; then
      read -r -p "Deseja habilitar autenticação básica (usuário e senha)? [s/N]: " answer </dev/tty
      if [[ "${answer,,}" == "s" || "${answer,,}" == "y" ]]; then
        read -r -p "Digite o nome de usuário: " user </dev/tty
        read -r -s -p "Digite a senha: " pass1 </dev/tty; echo
        read -r -s -p "Confirme a senha: " pass2 </dev/tty; echo
        [[ "$pass1" == "$pass2" ]] || die "As senhas não conferem."
        AUTH="${user}:${pass1}"
      fi
    fi
  elif [[ "$NO_INTERACTIVE" = false ]]; then
    warn "Sem terminal disponível; usando valores padrão/flags (porta $PORT)."
  fi

  validate_port "$PORT"
  [[ -z "$AUTH" ]] || validate_auth "$AUTH"

  latest=$(get_latest_tag)
  log "Iniciando instalação da versão $latest..."
  fetch_binary "$latest"

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log "Parando serviço existente..."
    systemctl stop "${SERVICE_NAME}.service"
  fi

  if port_in_use "$PORT"; then
    warn "A porta $PORT já está em uso por outro processo."
  fi

  install_binary
  echo "$latest" > "$VERSION_FILE"
  prune_backups

  ensure_service_user
  prepare_work_dir
  write_service

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service" >/dev/null
  systemctl restart "${SERVICE_NAME}.service"

  if wait_healthy; then
    log "✅ Serviço iniciado. Status:"
  else
    warn "O serviço não permaneceu ativo. Últimos logs:"
    journalctl -u "${SERVICE_NAME}" -n 30 --no-pager >&2 || true
  fi
  systemctl status "${SERVICE_NAME}.service" --no-pager || true

  echo ""
  echo "🌐 Acesse: http://localhost:${PORT}/"
  if [[ -n "$AUTH" ]]; then
    echo "🔐 Autenticação básica ativada (usuário: ${AUTH%%:*})."
    echo "   Exemplo: curl -u '${AUTH%%:*}' http://localhost:${PORT}/   (o curl pede a senha)"
    echo "   Credenciais guardadas em $ENV_FILE (somente root)."
  else
    warn "Autenticação básica DESATIVADA: proteja a porta $PORT (firewall/reverse proxy)."
  fi
}

# --- LÓGICA PRINCIPAL --------------------------------------------------------
if [[ "$UNINSTALL" = true ]]; then
  do_uninstall
elif [[ -f "$SERVICE_PATH" && "$RESET_SERVICE" = false ]]; then
  do_update
else
  do_install
fi
