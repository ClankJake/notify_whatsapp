# notify_whatsapp

Ferramentas para enviar notificações do seu servidor de mídia para o WhatsApp usando o [go-whatsapp-web-multidevice](https://github.com/aldinokemal/go-whatsapp-web-multidevice) (GOWA).

O repositório tem duas partes:

| Arquivo | O que faz |
| --- | --- |
| `install_go-whatsapp.sh` | Instala, atualiza e remove o GOWA como serviço `systemd` |
| `notify_whatsapp.py` | Script acionado pelo Tautulli que envia notificações de mídia do Plex para o WhatsApp (via GOWA) e para o Telegram |

> ⚠️ O GOWA é um cliente **não oficial** do WhatsApp. O número conectado pode ser banido, então use um número que você possa perder.

---

## Índice

- [Requisitos](#requisitos)
- [Instalação do GOWA](#instalação-do-gowa)
- [Opções (flags)](#opções-flags)
- [Exemplos](#exemplos)
- [Depois de instalar](#depois-de-instalar)
- [Atualização](#atualização)
- [Desinstalação](#desinstalação)
- [Segurança](#segurança)
- [Solução de problemas](#solução-de-problemas)
- [notify_whatsapp.py](#notify_whatsapppy)

---

## Requisitos

- Linux com `systemd`
- Arquitetura `x86_64`, `aarch64`/`arm64`, `armv7l` ou `i386`/`i686`
- Acesso `root` (ou `sudo`)
- Comandos: `curl`, `unzip`, `sha256sum`, `awk`, `find`, `install`, `sed`, `useradd`

No Debian/Ubuntu: `sudo apt install curl unzip`

## Instalação do GOWA

Instalação direta (pergunta a porta e se você quer autenticação básica):

```bash
curl -fsSL https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh | sudo bash
```

Se preferir ler o script antes de executar (recomendado):

```bash
curl -fsSLO https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh
less install_go-whatsapp.sh
sudo bash install_go-whatsapp.sh
```

O instalador:

1. descobre a versão mais recente do GOWA e baixa o binário da sua arquitetura;
2. **verifica o SHA-256** do download contra o `checksums.txt` do release;
3. instala o binário em `/usr/local/bin/go-whatsapp-web`;
4. cria o usuário de sistema `gowa` e o diretório de dados `/var/lib/go-whatsapp-web`;
5. cria, habilita e inicia o serviço `go-whatsapp-web.service`.

Rodar o mesmo comando de novo **atualiza** o GOWA, se houver versão nova.

## Opções (flags)

| Flag | Descrição |
| --- | --- |
| `--no-interactive` | Não faz perguntas; usa as flags abaixo ou os padrões (porta `3000`, sem autenticação) |
| `--port=PORTA` | Porta do servidor (padrão: `3000`) |
| `--basic-auth=USUARIO:SENHA` | Habilita autenticação básica |
| `--trusted-proxies=CIDR` | Proxies confiáveis (padrão: `0.0.0.0/0`) |
| `--user=NOME` | Usuário que executa o serviço (padrão: o já configurado ou `gowa`) |
| `--force-update` | Reinstala o binário mesmo já estando na versão mais recente |
| `--reset-service` | Recria o `go-whatsapp-web.service` (mantém dados e sessão); útil para restaurar um serviço quebrado ou aplicar novas opções |
| `--skip-checksum` | Pula a verificação do SHA-256 (não recomendado) |
| `--uninstall` | Remove binário e serviço, mantendo a sessão |
| `--purge` | Junto com `--uninstall`, apaga também os dados (**desconecta o WhatsApp**) |
| `-h`, `--help` | Mostra a ajuda |

Para passar flags quando o script vem do `curl`, use `bash -s --` (e `sudo` no `bash`):

```bash
curl -fsSL https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh | sudo bash -s -- --reset-service
```

## Exemplos

Instalação sem perguntas, em outra porta:

```bash
curl -fsSL https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh \
  | sudo bash -s -- --no-interactive --port=8080
```

Instalação sem perguntas **com autenticação**. Prefira a variável de ambiente, porque a senha não fica no histórico nem em `ps`:

```bash
curl -fsSL https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh \
  | sudo GOWA_BASIC_AUTH='usuario:senha' bash -s -- --no-interactive --port=8080
```

Recriar o serviço (por exemplo, para ativar autenticação depois):

```bash
sudo bash install_go-whatsapp.sh --reset-service
```

## Depois de instalar

Acesse `http://IP_DO_SERVIDOR:PORTA/` e conecte o WhatsApp lendo o QR code, como em "Aparelhos conectados".

Comandos úteis:

```bash
sudo systemctl status go-whatsapp-web      # estado do serviço
sudo systemctl restart go-whatsapp-web     # reiniciar
sudo journalctl -u go-whatsapp-web -f      # logs em tempo real
```

Com autenticação básica ativa, teste a API com:

```bash
curl -u usuario http://localhost:3000/     # o curl pede a senha
```

Arquivos criados:

| Caminho | Conteúdo |
| --- | --- |
| `/usr/local/bin/go-whatsapp-web` | Binário |
| `/usr/local/bin/go-whatsapp-web.version` | Versão instalada |
| `/etc/systemd/system/go-whatsapp-web.service` | Unit do systemd |
| `/etc/go-whatsapp-web.env` | Credenciais (só existe com autenticação; modo `600`, somente root) |
| `/var/lib/go-whatsapp-web/` | Dados e sessão do WhatsApp |

## Atualização

Basta rodar o instalador novamente:

```bash
curl -fsSL https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh | sudo bash
```

- O novo binário é baixado e verificado **antes** de parar o serviço.
- Um backup do binário anterior é salvo em `/usr/local/bin/go-whatsapp-web.bak.*` (os 3 mais recentes são mantidos).
- Se o serviço não subir com a nova versão, o backup é restaurado automaticamente.

## Desinstalação

```bash
sudo bash install_go-whatsapp.sh --uninstall           # mantém a sessão
sudo bash install_go-whatsapp.sh --uninstall --purge   # apaga tudo, inclusive a sessão
```

## Segurança

- **Ative a autenticação básica** se a porta for acessível fora da máquina, ou deixe-a atrás de um reverse proxy ou firewall. Sem autenticação, qualquer pessoa com acesso à porta pode enviar mensagens pelo seu número.
- `--trusted-proxies` vem como `0.0.0.0/0`. Isso só é adequado atrás de um proxy seu, como o nginx; caso contrário, restrinja ao IP do proxy.
- A senha fica em `/etc/go-whatsapp-web.env`, e não no arquivo do serviço (que é legível por todos).
- O serviço roda com usuário dedicado sem shell e com restrições do systemd (`NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, `PrivateTmp`).
- O checksum garante que o download não foi corrompido nem alterado em trânsito. Ele não substitui a confiança no projeto upstream.

## Solução de problemas

**O serviço não sobe.** Veja os logs com `sudo journalctl -u go-whatsapp-web -n 50 --no-pager`.

**Porta em uso.** Rode de novo com outra porta: `sudo bash install_go-whatsapp.sh --reset-service --port=8080`.

**Erro de permissão em arquivos.** O serviço tem escrita apenas em `/var/lib/go-whatsapp-web`. Se algo precisar escrever em outro lugar, comente as linhas de hardening (`ProtectSystem`, `ProtectHome`, `ReadWritePaths`) no unit, depois `sudo systemctl daemon-reload && sudo systemctl restart go-whatsapp-web`.

**"Checksum inválido".** O download foi descartado. Tente de novo; se persistir, confira o release no GitHub. Use `--skip-checksum` só se tiver certeza do que está fazendo.

**Arquitetura não suportada.** O instalador cobre `amd64`, `arm64`, `armv7` e `386`.

## notify_whatsapp.py

Script de notificação acionado pelo **Tautulli**: quando algo novo chega ao Plex, ele envia a notificação para o WhatsApp (via GOWA) e para o Telegram.

<!-- Complete esta seção com os detalhes do script: -->
<!-- - Dependências Python e como instalar -->
<!-- - Variáveis/configuração (URL e credenciais do GOWA, token do Telegram, IDs de destino) -->
<!-- - Como cadastrar o script no Tautulli (Settings → Notification Agents → Script) e quais argumentos passar -->
<!-- - Exemplo de mensagem recebida -->

## Licença

Defina a licença do projeto (por exemplo, MIT) adicionando um arquivo `LICENSE` ao repositório.
