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
for cmd in curl unzip grep id systemctl base64; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Erro: O comando '$cmd' é necessário, mas não foi encontrado. Por favor, instale-o (ex: sudo apt install $cmd)." >&2
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

# Função para baixar e extrair o binário de um arquivo ZIP
download_and_extract_binary() {
    local url="$1"
    local final_destination="$2"
    local filename
    filename=$(basename "$url")
    # Cria um diretório temporário seguro
    local tmp_dir
    tmp_dir=$(mktemp -d)

    log "Verificando URL de download..."
    echo "   URL: $url" >&2

    # Verifica se o URL é válido antes de tentar baixar
    if ! curl -s --head --fail "$url" > /dev/null; then
        echo "❌ ERRO: O arquivo de download não foi encontrado na URL acima." >&2
        echo "   Por favor, verifique se a versão mais recente possui um binário para sua arquitetura." >&2
        exit 1
    fi

    log "Baixando arquivo ZIP..."
    if ! curl -L -f -# -o "$tmp_dir/$filename" "$url"; then
        echo "❌ ERRO: Falha ao baixar o arquivo ZIP de $url." >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    log "Extraindo binário..."
    # Detecta o nome do executável, ignorando arquivos de texto como readme.md
    local executable_name
    executable_name=$(unzip -Z -1 "$tmp_dir/$filename" | grep -v -i -E 'readme.md|LICENSE' | head -n 1)
    if [ -z "$executable_name" ]; then
        echo "❌ ERRO: Não foi possível encontrar um arquivo executável dentro do ZIP." >&2
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    log "Nome do executável detectado: $executable_name"
    if ! unzip -o "$tmp_dir/$filename" "$executable_name" -d "$tmp_dir"; then
        echo "❌ ERRO: Falha ao extrair o binário do arquivo ZIP." >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    log "Instalando binário em $final_destination..."
    if ! mv "$tmp_dir/$executable_name" "$final_destination"; then
        echo "❌ ERRO: Falha ao mover o binário para o destino." >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    log "Limpando arquivos temporários..."
    rm -rf "$tmp_dir"
    log "✅ Binário instalado com sucesso."
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

# Detectar arquitetura para o novo formato de nome de arquivo
OS_NAME="linux"
ARCH=$(uname -m)
case "$ARCH" in
  "x86_64") BIN_ARCH="amd64" ;;
  "aarch64") BIN_ARCH="arm64" ;;
  "i386" | "i686") BIN_ARCH="386" ;;
  *)
    echo "❌ Arquitetura $ARCH não suportada." >&2
    exit 1
    ;;
esac

# === PARÂMETROS ===
NO_INTERACTIVE=false
RESET_SERVICE=false
FORCE_UPDATE=false

for arg in "$@"; do
  case "$arg" in
    --no-interactive)
      NO_INTERACTIVE=true
      ;;
    --reset-service)
      RESET_SERVICE=true
      ;;
    --force-update)
      FORCE_UPDATE=true
      ;;
    *)
      echo "Opção inválida: $arg" >&2
      echo "Uso: $0 [--no-interactive] [--reset-service] [--force-update]" >&2
      exit 1
      ;;
  esac
done

# === MODO DE ATUALIZAÇÃO AUTOMÁTICA ===
if [ -f "$SERVICE_PATH" ] && [ "$RESET_SERVICE" = false ]; then
  if [ "$FORCE_UPDATE" = true ]; then
    log "⚠️  Forçando a reinstalação da versão mais recente..."
  else
    log "Serviço já existente detectado. Verificando versão..."
  fi

  LATEST_TAG=$(get_latest_tag)

  INSTALLED_VERSION="none"
  if [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
  fi

  # Pular verificação de versão se --force-update for usado
  if [ "$INSTALLED_VERSION" == "$LATEST_TAG" ] && [ "$FORCE_UPDATE" = false ]; then
    log "✅ Já está na versão mais recente: $INSTALLED_VERSION"
    log "   (Use --force-update para reinstalar a mesma versão)"
    exit 0
  fi

  if [ "$FORCE_UPDATE" = true ] && [ "$INSTALLED_VERSION" == "$LATEST_TAG" ]; then
      log "📦 Reinstalando a versão $LATEST_TAG..."
  else
      log "📦 Atualizando da versão $INSTALLED_VERSION para $LATEST_TAG..."
  fi
  
  systemctl stop go-whatsapp-web.service

  VERSION_NUM=${LATEST_TAG#v} # Remove o prefixo 'v' (ex: v7.3.1 -> 7.3.1)
  FILENAME="whatsapp_${VERSION_NUM}_${OS_NAME}_${BIN_ARCH}.zip"
  LATEST_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/$LATEST_TAG/$FILENAME"
  
  BACKUP_PATH="$BIN_PATH.bak.$(date +%s)"
  [ -f "$BIN_PATH" ] && cp "$BIN_PATH" "$BACKUP_PATH" && log "🔙 Backup salvo: $BACKUP_PATH"

  download_and_extract_binary "$LATEST_URL" "$BIN_PATH"
  
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
VERSION_NUM=${LATEST_TAG#v}
FILENAME="whatsapp_${VERSION_NUM}_${OS_NAME}_${BIN_ARCH}.zip"
LATEST_URL="https://github.com/aldinokemal/go-whatsapp-web-multidevice/releases/download/$LATEST_TAG/$FILENAME"

download_and_extract_binary "$LATEST_URL" "$BIN_PATH"

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
