#!/bin/bash

# Variáveis fixas
REPO_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/latest"
BIN_PATH="/usr/local/bin/go-whatsapp-web"
SERVICE_PATH="/etc/systemd/system/go-whatsapp-web.service"
WORK_DIR="/var/lib/go-whatsapp-web"

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

SERVICE_EXISTS=false
if [ -f "$SERVICE_PATH" ]; then
  SERVICE_EXISTS=true
fi

if $SERVICE_EXISTS; then
  log "Serviço já existente detectado. Atualizando binário..."

  # Parar serviço
  systemctl stop go-whatsapp-web.service

  # Baixar nova versão
  LATEST_URL=$(curl -sL -o /dev/null -w "%{url_effective}" "$REPO_URL" | sed "s/tag/download/" | xargs -I {} echo {}/$BIN_ARCH)
  wget -q "$LATEST_URL" -O "$BIN_PATH" || {
    echo "Erro ao baixar o binário. Verifique a URL."
    exit 1
  }

  chmod +x "$BIN_PATH"

  log "Reiniciando o serviço..."
  systemctl daemon-reload
  systemctl start go-whatsapp-web.service
  systemctl status go-whatsapp-web.service --no-pager

  log "✅ Atualização concluída com sucesso!"
  exit 0
fi

# === ENTRADA INTERATIVA ===

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
  AUTH_STRING="--basic-auth=${AUTH_USER}:${AUTH_PASS}"
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
  echo "Erro ao baixar o binário. Verifique a URL."
  exit 1
}

chmod +x "$BIN_PATH"

# Preparar diretório de trabalho
mkdir -p "$WORK_DIR"
chown "$CURRENT_USER:$CURRENT_GROUP" "$WORK_DIR"

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

# Ativar serviço
systemctl daemon-reload
systemctl enable go-whatsapp-web.service
systemctl start go-whatsapp-web.service

log "Serviço iniciado. Status:"
systemctl status go-whatsapp-web.service --no-pager

# Exibir instrução de autenticação se tiver sido usada
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
