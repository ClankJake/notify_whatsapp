# notify_whatsapp

1. Script de instalação do go-whatsapp-web:
```
curl -s https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh | sudo bash
```

# Flags

--no-interactive: usa valores padrão sem perguntar nada (porta 3000, sem autenticação).

--reset-service: força a recriação do go-whatsapp-web.service, útil para editar manualmente ou restaurar um serviço quebrado.
 
Caso queira adicionar as flags veja o exemplo:

```
curl -s https://raw.githubusercontent.com/ClankJake/notify_whatsapp/main/install_go-whatsapp.sh | bash -s -- --reset-service
```
