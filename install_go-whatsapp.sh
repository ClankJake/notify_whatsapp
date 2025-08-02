#!/bin/bash

# Faz o script sair em caso de erro e falha em pipelines
set -e
set -o pipefail

# Variáveis fixas
REPO_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/latest"
BIN_PATH="/usr/local/bin/go-whatsapp-web"
SERVICE_PATH="/etc/systemd/system/go-whatsapp-web.service"
WORK_DIR="/var/lib/go-whatsapp-web"
VERSION_FILE="/usr/local/bin/go-whatsapp-web.version"

# Função para exibir mensagens de log no standard error para não interferir com a saída de dados
log() {
  echo "[INFO] $1" >&2
}

# --- BLOCO DE VERIFICAÇÕES INICIAIS ---

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Por favor, execute como root ou use sudo." >&2
  exit 1
fi

# Verificar dependências essenciais
for cmd in curl wget grep id systemctl base64; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Erro: O comando '$cmd' é necessário, mas não foi encontrado. Por favor, instale-o." >&2
    exit 1
  fi
done

# --- FUNÇÕES AUXILIARES ---

# Função para obter a tag mais recente do GitHub
get_latest_tag() {
  local tag
  log "Buscando a versão mais recente no GitHub..."
  tag=$(curl -sL -o /dev/null -w "%{url_effective}" "$REPO_URL" | grep -oP 'tag/\K[^/]+')
  if [ -z "$tag" ]; then
    echo "❌ Não foi possível obter a versão mais recente." >&2
    exit 1
  fi
  # Apenas a tag é enviada para o standard output para ser capturada
  echo "$tag"
}

# Função para baixar o binário usando curl para maior robustez
download_binary() {
    local url="$1"
    local destination="$2"

    log "Verificando URL de download..."
    echo "   URL: $url" >&2

    # Verifica se o URL é válido antes de tentar baixar
    if ! curl -s --head --fail "$url" > /dev/null; then
        echo "❌ ERRO: O arquivo de download não foi encontrado na URL acima." >&2
        echo "   Por favor, verifique se a versão mais recente possui um binário para sua arquitetura ($BIN_ARCH)." >&2
        exit 1
    fi

    log "Baixando binário..."
    # Usa curl para baixar: -L segue redirecionamentos, -f falha em erros de servidor, -# mostra barra de progresso.
    if ! curl -L -f -# -o "$destination" "$url"; then
        echo "❌ ERRO: Falha ao baixar o binário de $url." >&2
        # Limpa o arquivo parcial que o curl pode ter deixado
        rm -f "$destination"
        exit 1
    fi
    log "✅ Download concluído."
}


# --- LÓGICA PRINCIPAL ---

# Detectar usuário real
if [ -n "$SUDO_USER" ]; then
  CURRENT_USER="$SUDO_USER"
  CURRENT_GROUP=$(id -gn "$SUDO_USER")
else
  CURRENT_USER=$(whoami)
  CURRENT_GROUP=$(id -gn)
fi

# Detectar arquitetura
ARCH=$(uname -m)
case "$ARCH" in
  "x86_64") BIN_ARCH="linux-amd64" ;;
  "aarch64") BIN_ARCH="linux-arm64" ;;
  *)
    echo "❌ Arquitetura $ARCH não suportada." >&2
    exit 1
    ;;
esac

# === PARÂMETROS ===
NO_INTERACTIVE=false
RESET_SERVICE=false

for arg in "$@"; do
  case "$arg" in
    --no-interactive)
      NO_INTERACTIVE=true
      ;;
    --reset-service)
      RESET_SERVICE=true
      ;;
    *)
      echo "Opção inválida: $arg" >&2
      echo "Uso: $0 [--no-interactive] [--reset-service]" >&2
      exit 1
      ;;
  esac
done

# === MODO DE ATUALIZAÇÃO AUTOMÁTICA ===
if [ -f "$SERVICE_PATH" ] && [ "$RESET_SERVICE" = false ]; then
  log "Serviço já existente detectado. Verificando versão..."

  LATEST_TAG=$(get_latest_tag)

  INSTALLED_VERSION="none"
  if [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
  fi

  if [ "$INSTALLED_VERSION" == "$LATEST_TAG" ]; then
    log "✅ Já está na versão mais recente: $INSTALLED_VERSION"
    exit 0
  fi

  log "📦 Atualizando da versão $INSTALLED_VERSION para $LATEST_TAG..."
  systemctl stop go-whatsapp-web.service

  LATEST_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/$LATEST_TAG/$BIN_ARCH"
  BACKUP_PATH="$BIN_PATH.bak.$(date +%s)"
  [ -f "$BIN_PATH" ] && cp "$BIN_PATH" "$BACKUP_PATH" && log "🔙 Backup salvo: $BACKUP_PATH"

  download_binary "$LATEST_URL" "$BIN_PATH"
  
  chmod +x "$BIN_PATH"
  echo "$LATEST_TAG" > "$VERSION_FILE"

  systemctl daemon-reload
  systemctl start go-whatsapp-web.service

  log "✅ Atualizado para versão $LATEST_TAG"
  exit 0
fi

# === MODO INTERATIVO OU PRIMEIRA INSTALAÇÃO ===
PORT="3000"
AUTH_STRING=""
AUTH_USER=""
AUTH_PASS=""

if [ "$NO_INTERACTIVE" = false ]; then
  read -p "Digite a porta para o servidor (padrão: 3000): " INPUT_PORT </dev/tty
  PORT=${INPUT_PORT:-3000}

  read -p "Deseja habilitar autenticação básica (usuário e senha)? [s/N]: " USE_AUTH </dev/tty
  USE_AUTH=${USE_AUTH,,}
  if [[ "$USE_AUTH" == "s" || "$USE_AUTH" == "y" ]]; then
    read -p "Digite o nome de usuário: " AUTH_USER </dev/tty
    read -s -p "Digite a senha: " AUTH_PASS </dev/tty
    echo ""
    if [[ -n "$AUTH_USER" && -n "$AUTH_PASS" ]]; then
      AUTH_STRING="--basic-auth=${AUTH_USER}:${AUTH_PASS}"
    fi
  fi
else
  PORT="3000"
  AUTH_STRING=""
fi

# Parar serviço se rodando
if systemctl is-active --quiet go-whatsapp-web.service; then
  log "Parando serviço existente..."
  systemctl stop go-whatsapp-web.service
fi

# Baixar binário mais recente
LATEST_TAG=$(get_latest_tag)
log "Iniciando instalação da versão $LATEST_TAG..."
LATEST_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/$LATEST_TAG/$BIN_ARCH"

download_binary "$LATEST_URL" "$BIN_PATH"

chmod +x "$BIN_PATH"
echo "$LATEST_TAG" > "$VERSION_FILE"

# Criar diretório de trabalho
mkdir -p "$WORK_DIR"
chown "$CURRENT_USER:$CURRENT_GROUP" "$WORK_DIR"
chmod 700 "$WORK_DIR"

# Montar comando
EXEC_COMMAND="$BIN_PATH rest $AUTH_STRING --port=$PORT --os=Chrome --account-validation=false"

# Criar/Recriar systemd service
log "Criando arquivo systemd..."
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

# Habilitar e iniciar serviço
systemctl daemon-reload
systemctl enable go-whatsapp-web.service
systemctl start go-whatsapp-web.service

log "✅ Serviço iniciado. Status:"
systemctl status go-whatsapp-web.service --no-pager

# Mostrar autenticação básica
if [[ -n "$AUTH_USER" && -n "$AUTH_PASS" && "$NO_INTERACTIVE" = false ]]; then
  BASIC_AUTH_RAW="${AUTH_USER}:${AUTH_PASS}"
  BASIC_AUTH_ENCODED=$(echo -n "$BASIC_AUTH_RAW" | base64)

  echo ""
  echo "🔐 Autenticação básica ativada:"
  echo "   Usuário: $AUTH_USER"
  echo "   Senha: (oculta)"
  echo ""
  echo "📋 Use este header:"
  echo "   Authorization: Basic $BASIC_AUTH_ENCODED"
  echo ""
  echo "Exemplo com curl:"
  echo "   curl -H 'Authorization: Basic $BASIC_AUTH_ENCODED' http://localhost:$PORT/"
fi
