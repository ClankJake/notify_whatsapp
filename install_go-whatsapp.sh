#!/bin/bash

# Variáveis fixas
REPO_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/latest"
BIN_PATH="/usr/local/bin/go-whatsapp-web"
SERVICE_PATH="/etc/systemd/system/go-whatsapp-web.service"
WORK_DIR="/var/lib/go-whatsapp-web"
VERSION_FILE="/usr/local/bin/go-whatsapp-web.version"

# Detectar usuário real
if [ -n "$SUDO_USER" ]; then
  CURRENT_USER="$SUDO_USER"
  CURRENT_GROUP=$(id -gn "$SUDO_USER")
else
  CURRENT_USER=$(whoami)
  CURRENT_GROUP=$(id -gn)
fi

# Função para exibir mensagens
log() {
  echo "[INFO] $1"
}

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root ou use sudo."
  exit 1
fi

# Detectar arquitetura
ARCH=$(uname -m)
case "$ARCH" in
  "x86_64") BIN_ARCH="linux-amd64" ;;
  "aarch64") BIN_ARCH="linux-arm64" ;;
  *)
    echo "Arquitetura $ARCH não suportada."
    exit 1
    ;;
esac

# === MODO DE ATUALIZAÇÃO ===
if [ -f "$SERVICE_PATH" ]; then
  log "Serviço já existente detectado. Verificando versão..."

  # Obter versão mais recente do GitHub
  LATEST_TAG=$(curl -sL -o /dev/null -w "%{url_effective}" "$REPO_URL" | grep -oP 'tag/\K[^/]+')

  if [ -z "$LATEST_TAG" ]; then
    echo "⚠️  Não foi possível obter a versão mais recente do GitHub."
    exit 1
  fi

  # Verificar versão instalada
  INSTALLED_VERSION="none"
  if [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
  fi

  if [ "$INSTALLED_VERSION" == "$LATEST_TAG" ]; then
    log "✅ Já está na versão mais recente: $INSTALLED_VERSION"
    exit 0
  fi

  log "📦 Atualizando da versão $INSTALLED_VERSION para $LATEST_TAG..."

  # Parar serviço
  systemctl stop go-whatsapp-web.service

  # Determinar URL binário
  LATEST_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/$LATEST_TAG/$BIN_ARCH"

  # Fazer backup do binário anterior
  if [ -f "$BIN_PATH" ]; then
    BACKUP_PATH="$BIN_PATH.bak.$(date +%s)"
    cp "$BIN_PATH" "$BACKUP_PATH"
    log "🔙 Backup do binário anterior salvo como: $BACKUP_PATH"
  fi

  # Baixar nova versão
  wget -q "$LATEST_URL" -O "$BIN_PATH" || {
    echo "❌ Erro ao baixar o binário. Verifique a URL."
    exit 1
  }

  chmod +x "$BIN_PATH"
  echo "$LATEST_TAG" > "$VERSION_FILE"

  log "🔄 Reiniciando o serviço..."
  systemctl daemon-reload
  systemctl start go-whatsapp-web.service
  systemctl status go-whatsapp-web.service --no-pager

  log "✅ Atualização concluída para versão $LATEST_TAG!"
  exit 0
fi

# === MODO DE INSTALAÇÃO INTERATIVA ===

# Porta
read -p "Digite a porta para o servidor (padrão: 3000): " PORT </dev/tty
PORT=${PORT:-3000}

# Autenticação
read -p "Deseja habilitar autenticação básica (usuário e senha)? [s/N]: " USE_AUTH </dev/tty
USE_AUTH=${USE_AUTH,,}
AUTH_STRING=""

if [[ "$USE_AUTH" == "s" || "$USE_AUTH" == "y" ]]; then
  read -p "Digite o nome de usuário: " AUTH_USER </dev/tty
  read -s -p "Digite a senha: " AUTH_PASS </dev/tty
  echo ""

  if [[ -n "$AUTH_USER" && -n "$AUTH_PASS" ]]; then
    AUTH_STRING="--basic-auth=${AUTH_USER}:${AUTH_PASS}"
  else
    echo "⚠️  Usuário ou senha não fornecidos. Autenticação não será ativada."
    AUTH_STRING=""
  fi
fi

# Parar serviço se ativo
if systemctl is-active --quiet go-whatsapp-web.service; then
  log "Parando serviço existente..."
  systemctl stop go-whatsapp-web.service
fi

# Obter binário mais recente
log "Baixando binário mais recente..."
LATEST_URL=$(curl -sL -o /dev/null -w "%{url_effective}" "$REPO_URL" | sed "s/tag/download/" | xargs -I {} echo {}/$BIN_ARCH)

wget -q "$LATEST_URL" -O "$BIN_PATH" || {
  echo "❌ Erro ao baixar o binário. Verifique a URL."
  exit 1
}

chmod +x "$BIN_PATH"

# Salvar versão atual
LATEST_TAG=$(curl -sL -o /dev/null -w "%{url_effective}" "$REPO_URL" | grep -oP 'tag/\K[^/]+')
echo "$LATEST_TAG" > "$VERSION_FILE"

# Preparar diretório de trabalho
mkdir -p "$WORK_DIR"
chown "$CURRENT_USER:$CURRENT_GROUP" "$WORK_DIR"
chmod 700 "$WORK_DIR"

# Linha do ExecStart
EXEC_COMMAND="$BIN_PATH rest $AUTH_STRING --port=$PORT --os=Chrome --account-validation=false"

# Criar serviço systemd
log "Criando serviço systemd..."
cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=Go WhatsApp Web Multi-Device
After=network.target

[Service]
ExecStart=$EXEC_COMMAND
Restart=on-failure
User=$CURRENT_USER
Group=$CURRENT_GROUP
WorkingDirectory=$WORK_DIR
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Ativar e iniciar serviço
systemctl daemon-reload
systemctl enable go-whatsapp-web.service
systemctl start go-whatsapp-web.service

log "✅ Serviço iniciado. Status:"
systemctl status go-whatsapp-web.service --no-pager

# Exibir instrução de autenticação se usada
if [[ "$AUTH_STRING" != "" ]]; then
  BASIC_AUTH_RAW="${AUTH_USER}:${AUTH_PASS}"
  BASIC_AUTH_ENCODED=$(echo -n "$BASIC_AUTH_RAW" | base64)

  echo ""
  echo "🔐 Autenticação básica ativada:"
  echo "  Usuário: $AUTH_USER"
  echo "  Senha: (oculta)"
  echo ""
  echo "📋 Use este header em clientes que suportam autenticação HTTP Basic:"
  echo "  Authorization: Basic $BASIC_AUTH_ENCODED"
  echo ""
  echo "Exemplo com curl:"
  echo "  curl -H 'Authorization: Basic $BASIC_AUTH_ENCODED' http://localhost:$PORT/"
fi
