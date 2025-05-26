#!/bin/bash

# Variáveis de configuração
REPO_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/latest"
BIN_PATH="/usr/local/bin/go-whatsapp-web"
SERVICE_PATH="/etc/systemd/system/go-whatsapp-web.service"
WORK_DIR="/var/lib/go-whatsapp-web"
PORT="3000"
AUTH_USER="admin"
AUTH_PASS="caverna7"
OS_TYPE="Chrome"

# Capturando o usuário e grupo atuais
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

# Verificar se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root ou use sudo."
  exit 1
fi

# Determinando arquitetura
ARCH=$(uname -m)
case "$ARCH" in
  "x86_64")
    BIN_ARCH="linux-amd64"
    ;;
  "aarch64")
    BIN_ARCH="linux-arm64"
    ;;
  *)
    echo "Arquitetura $ARCH não suportada."
    exit 1
    ;;
esac

# Parando o serviço se estiver rodando
if systemctl is-active --quiet go-whatsapp-web.service; then
  log "Parando o serviço para atualização..."
  systemctl stop go-whatsapp-web.service
fi

# Obtendo a URL do binário mais recente
log "Obtendo a URL do binário mais recente..."
LATEST_URL=$(curl -sL -o /dev/null -w "%{url_effective}" "$REPO_URL" | sed "s/tag/download/" | xargs -I {} echo {}/$BIN_ARCH)
if [ -z "$LATEST_URL" ]; then
  echo "Erro ao obter a URL do binário. Verifique o repositório."
  exit 1
fi

log "Baixando o binário..."
wget -q "$LATEST_URL" -O "$BIN_PATH"
if [ $? -ne 0 ]; then
  echo "Erro ao baixar o binário. Verifique a URL."
  exit 1
fi

log "Tornando o binário executável..."
chmod +x "$BIN_PATH"

log "Criando diretório de trabalho..."
mkdir -p "$WORK_DIR"
chown "$CURRENT_USER:$CURRENT_GROUP" "$WORK_DIR"

log "Configurando o serviço systemd..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Go WhatsApp Web Multi-Device
After=network.target

[Service]
ExecStart=$BIN_PATH rest --basic-auth=${AUTH_USER}:${AUTH_PASS} --port=${PORT} --os=${OS_TYPE} --account-validation=false
Restart=on-failure
User=$CURRENT_USER
Group=$CURRENT_GROUP
WorkingDirectory=$WORK_DIR
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log "Recarregando daemon do systemd..."
systemctl daemon-reload

log "Ativando o serviço para iniciar automaticamente..."
systemctl enable go-whatsapp-web.service

log "Iniciando o serviço..."
systemctl start go-whatsapp-web.service

log "Verificando o status do serviço..."
systemctl status go-whatsapp-web.service --no-pager

log "Instalação e configuração concluídas!"
