#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Script de notificação Tautulli para WhatsApp com informações de áudio.

1. Instale o módulo requests para python:
      pip install requests

2. Tautulli > Settings > Notification Agents > Scripts > Bell icon:
      [X] Notify on Recently Added

3. Tautulli > Settings > Notification Agents > Scripts > Gear icon:
      Playback Recently Added: notify_whatsapp_audio.py (ou o nome deste arquivo)

4. Tautulli > Settings > Notifications > Script > Script Arguments:
   !!! IMPORTANTE: Adicione o -rk {rating_key} !!!
      -servn {server_name} -ds {datestamp:DD/MM/YYYY} -st {studio} -di {directors} -ac {\\n👨‍👩‍👦‍👦\ *Elenco:*\ <actors:[:4]} 
      -dt {duration_time:HH:mm:ss} -vw {video_width} -vh {video_height} -fs {file_size} -sy {show_year}  -sn {show_name} 
      -ena {episode_name} -ssn {season_num00} -enu {episode_num00} -dur {duration} -med {media_type} -tt {title} 
      -pos {poster_url} -genres {genres} -rating {\\n👍🏼\ *Avaliação:*\ <rating>/10} -summary {\\n\\n*Sinopse:*\ <summary} 
      -year {year} -lname {library_name} -vr {video_resolution} -cr {content_rating} -rk {rating_key}

5. Argumentos Opcionais:
      -auth -log

6. Preencha as seções 'CONFIGURAÇÕES WHATSAPP' e 'CONFIGURAÇÕES TAUTULLI' abaixo.
"""

from __future__ import unicode_literals
import argparse
import requests
import time
import sys
from collections import defaultdict

# --- CONFIGURAÇÕES WHATSAPP ---
CONFIG_WHATSAPP = {
    "webhook_url": 'http://you_ip:3000/send/image',
    "phone": 'you_id@s.whatsapp.net', # Para Canal: @newsletter, Grupo: @g.us, Privado: @s.whatsapp.net
    "token": 'Basic SUA CREDENCIAL', # Opicional. Caso tenha colocado autenticao no go-whatsapp-web-multidevice
}

# --- CONFIGURAÇÕES TAUTULLI ---
# Necessário para buscar informações de áudio
CONFIG_TAUTULLI = {
    "tautulli_url": "http://SEU_IP_DO_TAUTULLI:8181", # URL base do seu Tautulli
    "tautulli_apikey": "SUA_API_KEY_DO_TAUTULLI",      # Encontre em Tautulli > Settings > Web Interface > API
}

# --- GERAL ---
CONFIG_GERAL = {
    "log_file_path": '/config/notify_whatsapp.log' # Caminho para o arquivo de log
}

# --- TEMPLATES DE MENSAGEM ---
# Adicionado {audio_info} para filmes e episódios
TEMPLATES = {

    "movie": "🍿 *Título:* {title} ({year})\n"
             "🕓 *Duração:* {duration} minutos\n"
             "🎭 *Gênero:* {genres} {actors} {audio_info} {rating} {summary}",

    "episode": "🍿 *Título:* {show_name} ({year})\n"
               "🔢 *Episódio:* {season_num}x{episode_num} - {episode_name}\n"
               "🕓 *Duração:* {duration} minutos\n"
               "🎭 *Gênero:* {genres} {actors} {audio_info} {rating} {summary}",

    "show": "🍿 *Título:* {show_name} ({show_year})\n"
            "🎭 *Gênero:* {genres} {actors} {rating} {summary}",

    "season": "🍿 *Título:* {show_name} ({show_year})\n"
              "🎬 *Temporada:* {season_num}\n"
              "🎭 *Gênero:* {genres} {actors} {rating} {summary}"
}

# --- MAPA DE IDIOMAS ---
# Mapeia códigos de 3 letras (ISO 639-2) para nomes completos
LANGUAGE_CODES = {
    # Principais
    'por': 'Português',
    'eng': 'Inglês',
    'jpn': 'Japonês',
    'spa': 'Espanhol',
    'fre': 'Francês',
    'ger': 'Alemão',
    'ita': 'Italiano',
    'kor': 'Coreano',
    'chi': 'Chinês',
    'zho': 'Chinês',
    'rus': 'Russo',
    'und': 'Indefinido',
    
    # Adicionais (Europeus)
    'dut': 'Holandês',
    'pol': 'Polonês',
    'swe': 'Sueco',
    'nor': 'Norueguês',
    'fin': 'Finlandês',
    'dan': 'Dinamarquês',
    'gre': 'Grego',
    'cze': 'Tcheco',
    'hun': 'Húngaro',
    'rum': 'Romeno',
    'ukr': 'Ucraniano',
    'tur': 'Turco',
    'fra': 'Francês',

    # Adicionais (Ásia/Outros)
    'ara': 'Árabe',
    'hin': 'Hindi',
    'tha': 'Tailandês',
    'heb': 'Hebraico',
    'vie': 'Vietnamita',
    'ind': 'Indonésio',
    'srp': 'Sérvio',
    
    # Adicione mais códigos de 3 letras conforme necessário
    
    # Fallbacks de 2 letras (menos comum no Tautulli/Plex)
    'pt': 'Português',
    'en': 'Inglês',
    'ja': 'Japonês',
    'es': 'Espanhol',
    'fr': 'Francês',
    'de': 'Alemão',
    'it': 'Italiano',
    'ko': 'Coreano',
    'zh': 'Chinês',
    'ru': 'Russo',
    'nl': 'Holandês',
    'pl': 'Polonês',
    'sv': 'Sueco',
    'sr': 'Sérvio',
    'no': 'Norueguês',
    'fi': 'Finlandês',
    'da': 'Dinamarquês',
    'el': 'Grego',
    'cs': 'Tcheco',
    'hu': 'Húngaro',
    'ro': 'Romeno',
    'uk': 'Ucraniano',
    'tr': 'Turco',
    'ar': 'Árabe',
    'hi': 'Hindi',
    'th': 'Tailandês',
    'he': 'Hebraico',
    'vi': 'Vietnamita',
    'id': 'Indonésio',
}

# --- Funções Auxiliares ---

def log(message, log_enabled):
    """Grava uma mensagem de log no arquivo se o log estiver ativado."""
    if log_enabled:
        try:
            with open(CONFIG_GERAL['log_file_path'], 'a', encoding='utf-8') as log_file:
                log_file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")
        except Exception as e:
            # Se o log falhar, imprime no stderr para que o Tautulli possa capturar
            print(f"Erro ao escrever no log: {e}", file=sys.stderr)

def get_audio_info(rating_key, log_enabled):
    """Busca e formata informações de áudio da API Tautulli."""
    if not CONFIG_TAUTULLI["tautulli_apikey"] or not CONFIG_TAUTULLI["tautulli_url"]:
        log("TAUTULLI_URL ou TAUTULLI_APIKEY não configurados. Pulando busca de áudio.", log_enabled)
        return ""

    if not rating_key:
        log("Rating key não fornecido a -rk. Pulando busca de áudio.", log_enabled)
        return ""

    api_url = (f"{CONFIG_TAUTULLI['tautulli_url']}/api/v2"
               f"?apikey={CONFIG_TAUTULLI['tautulli_apikey']}"
               f"&cmd=get_metadata&rating_key={rating_key}")

    log(f"Buscando metadados de: {api_url}", log_enabled)

    try:
        response = requests.get(api_url, timeout=10)
        response.raise_for_status() 
        data = response.json()

        if data.get('response', {}).get('result') != 'success':
            log(f"API Tautulli retornou erro: {data.get('response', {}).get('message')}", log_enabled)
            return ""

        media_info = data.get('response', {}).get('data', {}).get('media_info', [])
        if not media_info:
            log("Nenhum 'media_info' encontrado no JSON.", log_enabled)
            return ""

        parts = media_info[0].get('parts', [])
        if not parts:
            log("Nenhum 'parts' encontrado no JSON.", log_enabled)
            return ""

        streams = parts[0].get('streams', [])
        if not streams:
            log("Nenhum 'streams' encontrado no JSON.", log_enabled)
            return ""

        audio_tracks = []
        for stream in streams:
            if stream.get('type') == '2':
                codec = stream.get('audio_codec', 'desconhecido').upper()
                
                lang_code = stream.get('audio_language_code')
                if not lang_code:
                    lang_code = 'und' # 'undetermined'
                
                lang_code = lang_code.lower()
                language = LANGUAGE_CODES.get(lang_code, lang_code.upper())
                # ------------------------------------

                layout_raw = stream.get('audio_channel_layout', '')
                layout = layout_raw.split('(')[0]
                if layout.lower() == 'stereo':
                    layout = '2.0'

                track_info = f"{language} ({layout})".strip()
                audio_tracks.append(track_info)

        if audio_tracks:
            return "\n🎵 *Áudio:* " + ", ".join(audio_tracks)
        else:
            log("Nenhuma faixa de áudio (type 2) encontrada nos streams.", log_enabled)
            return ""

    except requests.exceptions.RequestException as e:
        log(f"Erro ao chamar API Tautulli: {e}", log_enabled)
        return ""
    except Exception as e:
        log(f"Erro ao analisar JSON do Tautulli: {e}", log_enabled)
        return ""


def build_arguments():
    """Build and parse command-line arguments."""
    parser = argparse.ArgumentParser()

    arguments = [
        ('-servn', '--server_name', 'Server Name', '', None),
        ('-ds', '--datestamp', 'Date', '', None),
        ('-med', '--media_type', 'Media type (e.g., movie, episode)', '', None),
        ('-tt', '--title', 'Media title', '', None),
        ('-sn', '--show_name', 'TV show name', '', None),
        ('-ena', '--episode_name', 'Episode name', '', None),
        ('-ssn', '--season_num', 'Season number', '', None),
        ('-enu', '--episode_num', 'Episode number', '', None),
        ('-dur', '--duration', 'Duration', '', None),
        ('-genres', '--genres', 'Genres', '', None),
        ('-rating', '--rating', 'Rating', '', None),
        ('-summary', '--summary', 'Summary', '', None),
        ('-year', '--year', 'Release year', '', None),
        ('-lname', '--library_name', 'Library name', '', None),
        ('-pos', '--poster', 'Poster URL', '', None),
        ('-cr', '--content_rating', 'Content Rating', '', None),
        ('-st', '--studio', 'Studio', '', None),
        ('-di', '--directors', 'Directors', '', None),
        ('-ac', '--actors', 'Actors', '', None),
        ('-dt', '--duration_time', 'Duration Time', '', None),
        ('-vw', '--video_width', 'Video Width', '', None),
        ('-vh', '--video_height', 'Video Height', '', None),
        ('-vr', '--video_resolution', 'Video Resolution', '', None),
        ('-fs', '--file_size', 'File Size', '', None),
        ('-sy', '--show_year', 'Show Year', '', None),
        ('-rk', '--rating_key', 'Rating Key', '', None),
        ('-log', '--log_enabled', 'Enable logging', False, 'store_true'),
        ('-auth', '--auth', 'Enable Authorization header', False, 'store_true'),
    ]

    for short, long, help_text, default, action in arguments:
        if action:
            parser.add_argument(short, long, help=help_text, default=default, action=action)
        else:
            parser.add_argument(short, long, help=help_text, default=default)

    return parser.parse_args()

def send_webhook(body_text, poster_url, log_enabled, auth_enabled):
    """Envia os dados para o webhook."""
    try:
        headers = {}
        if auth_enabled:
            headers['Authorization'] = CONFIG_WHATSAPP['token']

        multipart_data = {
            'phone': (None, CONFIG_WHATSAPP['phone']),
            'image_url': (None, poster_url),
            'caption': (None, body_text),
            'compress': (None, 'true')
        }

        response = requests.post(CONFIG_WHATSAPP['webhook_url'], files=multipart_data, headers=headers, timeout=15)
        log(f"Webhook response: {response.status_code} - {response.text}", log_enabled)
        return response.status_code
    except Exception as e:
        log(f"Error sending webhook: {e}", log_enabled)
        return None

# --- Execução Principal ---

if __name__ == '__main__':
    args = build_arguments()
    log_enabled = args.log_enabled

    log("Script started", log_enabled)
    log(f"Arguments: {args}", log_enabled)

    if not args.poster:
        log("Poster URL is missing. Cannot send notification.", log_enabled)
        sys.exit() # Usar sys.exit()

    if args.media_type not in TEMPLATES:
        log(f"Unsupported media type: {args.media_type}", log_enabled)
        sys.exit()

    # Cria um dicionário com os argumentos, com valores padrão em caso de falta
    format_args = defaultdict(str, vars(args))

    # --- Lógica de Busca de Áudio ---
    audio_info = ""
    if args.media_type in ("movie", "episode"):
        audio_info = get_audio_info(args.rating_key, log_enabled)

    format_args['audio_info'] = audio_info
    # --------------------------------

    # Formata a mensagem principal
    try:
        body_text = TEMPLATES[args.media_type].format_map(format_args)
    except KeyError as e:
        log(f"Erro ao formatar template: chave {e} faltando.", log_enabled)
        sys.exit()

    # A API de imagem parece precisar de uma extensão
    poster_url_for_api = f"{args.poster}.png"
    log(f"Using modified URL for API: {poster_url_for_api}", log_enabled)

    # Envia a notificação
    send_webhook(body_text, poster_url_for_api, log_enabled, auth_enabled=args.auth)

    log("Script completed", log_enabled)
