import base64

def generate_basic_auth(login, senha):
    """Gera o cabeçalho Authorization no formato Basic."""
    credentials = f"{login}:{senha}"
    encoded_credentials = base64.b64encode(credentials.encode('utf-8')).decode('utf-8')
    return f"Basic {encoded_credentials}"

if __name__ == "__main__":
    login = input("Digite o login: ")
    senha = input("Digite a senha: ")
    
    basic_auth_header = generate_basic_auth(login, senha)
    print("\nCabeçalho Authorization gerado:")
    print(basic_auth_header)
