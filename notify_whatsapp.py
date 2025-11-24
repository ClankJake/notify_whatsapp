#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Script de notificação Tautulli para WhatsApp e Telegram com informações de áudio.

1. Instale o módulo requests para python:
      pip install requests

2. Configuração no Tautulli (Notification Agents):
   - Scripts > Bell icon: [X] Notify on Recently Added
   - Scripts > Gear icon: Playback Recently Added: Selecione este arquivo

3. Argumentos do Script (Script Arguments):
   !!! IMPORTANTE: Adicione o -rk {rating_key} !!!
      -servn {server_name} -ds {datestamp:DD/MM/YYYY} -st {studio} -di {directors} -ac {\\n👨‍👩‍👦‍👦\ *Elenco:*\ <actors:[:4]} 
      -dt {duration_time:HH:mm:ss} -vw {video_width} -vh {video_height} -fs {file_size} -sy {show_year}  -sn {show_name} 
      -ena {episode_name} -ssn {season_num00} -enu {episode_num00} -dur {duration} -med {media_type} -tt {title} 
      -pos {poster_url} -genres {genres} -rating {\\n👍🏼\ *Avaliação:*\ <rating>/10} -summary {\\n\\n*Sinopse:*\ <summary} 
      -year {year} -lname {library_name} -vr {video_resolution} -cr {content_rating} -rk {rating_key}

4. Preencha as seções 'CONFIGURAÇÕES' abaixo (WhatsApp e/ou Telegram).
"""

from __future__ import unicode_literals
import argparse
import requests
import time
import sys
import html
import re
from collections import defaultdict

# --- CONFIGURAÇÕES WHATSAPP ---
CONFIG_WHATSAPP = {
    "enabled": True, # Defina como False para desativar o WhatsApp
    "webhook_url": 'http://you_ip:3000/send/image',
    "token": 'Basic SUA CREDENCIAL', # Caso tenha colocado uma autenticao no go-whatsapp-web-multidevice
    "phone": 'you_id@s.whatsapp.net', # Para Canal: @newsletter, Grupo: @g.us, Privado: @s.whatsapp.net
}

# --- CONFIGURAÇÕES TELEGRAM ---
CONFIG_TELEGRAM = {
    "enabled": True, # Defina como False para desativar o Telegram
    "bot_token": 'SEU_BOT_TOKEN_AQUI', # Ex: 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
    "chat_id": 'SEU_CHAT_ID_AQUI'      # Ex: -100123456789 ou 12345678
}

# --- CONFIGURAÇÕES TAUTULLI ---
# Necessário para buscar informações de áudio
CONFIG_TAUTULLI = {
    "tautulli_url": "http://SEU_IP_DO_TAUTULLI:8181", # Ex: http://192.168.1.10:8181
    "tautulli_apikey": "SUA_API_KEY_DO_TAUTULLI",
}

# --- GERAL ---
CONFIG_GERAL = {
    "log_file_path": '/config/notify_unified.log' # Caminho para o arquivo de log
}

# --- TEMPLATES WHATSAPP (MARKDOWN) ---
TEMPLATES_WHATSAPP = {
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

# --- TEMPLATES TELEGRAM (HTML) ---
TEMPLATES_TELEGRAM = {
    "movie": "🍿 <b>Título:</b> {title} ({year})\n"
             "🕓 <b>Duração:</b> {duration} minutos\n"
             "🎭 <b>Gênero:</b> {genres} {actors} {audio_info} {rating}\n\n"
             "{summary}",

    "episode": "🍿 <b>Série:</b> {show_name} ({year})\n"
               "🔢 <b>Episódio:</b> {season_num}x{episode_num} - {episode_name}\n"
               "🕓 <b>Duração:</b> {duration} minutos\n"
               "🎭 <b>Gênero:</b> {genres} {actors} {audio_info} {rating}\n\n"
               "{summary}",

    "show": "🍿 <b>Título:</b> {show_name} ({show_year})\n"
            "🎭 <b>Gênero:</b> {genres} {actors} {rating}\n\n"
            "{summary}",

    "season": "🍿 <b>Título:</b> {show_name} ({show_year})\n"
              "🎬 <b>Temporada:</b> {season_num}\n"
              "🎭 <b>Gênero:</b> {genres} {actors} {rating}\n\n"
              "{summary}"
}

# --- MAPA DE IDIOMAS ---
LANGUAGE_CODES = {
    'por': 'Português', 'eng': 'Inglês', 'jpn': 'Japonês', 'spa': 'Espanhol',
    'fre': 'Francês', 'ger': 'Alemão', 'ita': 'Italiano', 'kor': 'Coreano',
    'chi': 'Chinês', 'zho': 'Chinês', 'rus': 'Russo', 'und': 'Indefinido',
    'dut': 'Holandês', 'pol': 'Polonês', 'swe': 'Sueco', 'nor': 'Norueguês',
    'fin': 'Finlandês', 'dan': 'Dinamarquês', 'gre': 'Grego', 'cze': 'Tcheco',
    'hun': 'Húngaro', 'rum': 'Romeno', 'ukr': 'Ucraniano', 'tur': 'Turco',
    'fra': 'Francês', 'ara': 'Árabe', 'hin': 'Hindi', 'tha': 'Tailandês',
    'heb': 'Hebraico', 'vie': 'Vietnamita', 'ind': 'Indonésio', 'srp': 'Sérvio',
    'pt': 'Português', 'en': 'Inglês', 'ja': 'Japonês', 'es': 'Espanhol',
    'fr': 'Francês', 'de': 'Alemão', 'it': 'Italiano', 'ko': 'Coreano',
    'zh': 'Chinês', 'ru': 'Russo', 'nl': 'Holandês', 'pl': 'Polonês',
    'sv': 'Sueco', 'sr': 'Sérvio', 'no': 'Norueguês', 'fi': 'Finlandês',
    'da': 'Dinamarquês', 'el': 'Grego', 'cs': 'Tcheco', 'hu': 'Húngaro',
    'ro': 'Romeno', 'uk': 'Ucraniano', 'tr': 'Turco', 'ar': 'Árabe',
    'hi': 'Hindi', 'th': 'Tailandês', 'he': 'Hebraico', 'vi': 'Vietnamita',
    'id': 'Indonésio',
}

# --- Funções Auxiliares ---

def log(message, log_enabled):
    if log_enabled:
        try:
            with open(CONFIG_GERAL['log_file_path'], 'a', encoding='utf-8') as log_file:
                log_file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")
        except Exception:
            pass

def get_audio_info(rating_key, log_enabled):
    if not CONFIG_TAUTULLI["tautulli_apikey"] or not CONFIG_TAUTULLI["tautulli_url"] or not rating_key:
        return ""

    api_url = (f"{CONFIG_TAUTULLI['tautulli_url']}/api/v2"
               f"?apikey={CONFIG_TAUTULLI['tautulli_apikey']}"
               f"&cmd=get_metadata&rating_key={rating_key}")

    try:
        response = requests.get(api_url, timeout=10)
        response.raise_for_status() 
        data = response.json()
        if data.get('response', {}).get('result') != 'success': return ""

        media_info = data.get('response', {}).get('data', {}).get('media_info', [])
        if not media_info or not media_info[0].get('parts') or not media_info[0].get('parts')[0].get('streams'):
            return ""

        streams = media_info[0]['parts'][0]['streams']
        audio_tracks = []
        for stream in streams:
            if stream.get('type') == '2':
                codec = stream.get('audio_codec', '').upper()
                lang_code = stream.get('audio_language_code', 'und').lower()
                language = LANGUAGE_CODES.get(lang_code, lang_code.upper())
                layout = stream.get('audio_channel_layout', '').split('(')[0]
                if layout.lower() == 'stereo': layout = '2.0'
                audio_tracks.append(f"{language} ({layout})".strip())

        return "\n🔊 <b>Áudio:</b> " + ", ".join(audio_tracks) if audio_tracks else ""

    except Exception as e:
        log(f"Erro ao buscar áudio: {e}", log_enabled)
        return ""

def build_arguments():
    parser = argparse.ArgumentParser()
    arguments = [
        ('-servn', '--server_name', 'Server Name', '', None),
        ('-ds', '--datestamp', 'Date', '', None),
        ('-med', '--media_type', 'Media type', '', None),
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
        ('-auth', '--auth', 'Enable Auth', False, 'store_true'),
    ]

    for short, long_arg, help_text, default, action in arguments:
        if action:
            parser.add_argument(short, long_arg, help=help_text, default=default, action=action)
        else:
            parser.add_argument(short, long_arg, help=help_text, default=default)

    return parser.parse_args()

def send_whatsapp_webhook(body_text, poster_url, log_enabled, auth_enabled):
    if not CONFIG_WHATSAPP.get("enabled", True): return

    try:
        headers = {}
        if auth_enabled: headers['Authorization'] = CONFIG_WHATSAPP['token']
        poster_url_fixed = f"{poster_url}.png" if not poster_url.endswith('.png') else poster_url

        multipart_data = {
            'phone': (None, CONFIG_WHATSAPP['phone']),
            'image_url': (None, poster_url_fixed),
            'caption': (None, body_text),
            'compress': (None, 'true')
        }
        requests.post(CONFIG_WHATSAPP['webhook_url'], files=multipart_data, headers=headers, timeout=15)
        log("WhatsApp enviado.", log_enabled)
    except Exception as e:
        log(f"Erro WhatsApp: {e}", log_enabled)

def send_telegram_html(body_html, poster_url, log_enabled):
    if not CONFIG_TELEGRAM.get("enabled", True): return
    if not CONFIG_TELEGRAM['bot_token'] or not CONFIG_TELEGRAM['chat_id']: return

    api_url = f"https://api.telegram.org/bot{CONFIG_TELEGRAM['bot_token']}/sendPhoto"
    poster_url_dl = f"{poster_url}.png" if not poster_url.endswith(('.png', '.jpg')) else poster_url

    try:
        data = {
            'chat_id': CONFIG_TELEGRAM['chat_id'],
            'caption': body_html,
            'parse_mode': 'HTML',
            'photo': poster_url_dl
        }
        response = requests.post(api_url, data=data, timeout=15)
        
        if response.status_code != 200:
            log(f"Telegram URL falhou ({response.status_code}), tentando upload...", log_enabled)
            img_response = requests.get(poster_url_dl, timeout=15)
            if img_response.status_code == 200:
                files = {'photo': ('image.png', img_response.content)}
                del data['photo']
                requests.post(api_url, data=data, files=files, timeout=20)
        
        log("Telegram enviado.", log_enabled)
    except Exception as e:
        log(f"Erro Telegram: {e}", log_enabled)

# --- Execução Principal ---

if __name__ == '__main__':
    args = build_arguments()
    log_enabled = args.log_enabled
    log("Script iniciado", log_enabled)

    if not args.poster: 
        log("Poster URL não fornecido.", log_enabled)
        sys.exit()
    if args.media_type not in TEMPLATES_WHATSAPP: 
        log(f"Media Type desconhecido: {args.media_type}", log_enabled)
        sys.exit()

    # --- 1. WHATSAPP (Markdown) ---
    wa_args = defaultdict(str, vars(args))
    if args.media_type in ("movie", "episode"):
        audio_html = get_audio_info(args.rating_key, log_enabled)
        wa_args['audio_info'] = audio_html.replace("<b>", "*").replace("</b>", "*")
    
    try:
        wa_body = TEMPLATES_WHATSAPP[args.media_type].format_map(wa_args)
        send_whatsapp_webhook(wa_body, args.poster, log_enabled, args.auth)
    except Exception as e:
        log(f"Erro Template WA: {e}", log_enabled)

    # --- 2. TELEGRAM (HTML) ---
    tg_args = defaultdict(str, vars(args))
    
    for key, value in tg_args.items():
        if isinstance(value, str):
            clean_val = html.escape(value)

            # LÓGICA DE SINOPSE
            if key == 'summary':
                clean_val = clean_val.strip()
                
                # Procura por "*Sinopse:*" seguido de QUALQUER texto
                match = re.match(r'\*(.*?)\*\s*(.*)', clean_val, re.DOTALL)
                
                if match:
                    label = match.group(1)   # "Sinopse:"
                    content = match.group(2).strip() # O texto da sinopse (removemos espaços)
                    
                    # VERIFICAÇÃO CRÍTICA: Se 'content' estiver vazio, não mostra nada
                    if content:
                        if len(content) > 600:
                            content = content[:600] + "..."
                        clean_val = f"ℹ️ <b>{label}</b>\n<blockquote>{content}</blockquote>"
                    else:
                        clean_val = "" # Conteúdo vazio -> string vazia (oculta)
                
                else:
                    # Fallback (caso o formato *Sinopse:* não venha, mas tenha texto)
                    if clean_val:
                        if len(clean_val) > 600: clean_val = clean_val[:600] + "..."
                        clean_val = f"ℹ️ <b>Sinopse:</b>\n<blockquote>{clean_val}</blockquote>"
                    else:
                         clean_val = ""

            else:
                # Outros campos (Elenco, Avaliação)
                try:
                    clean_val = re.sub(r'\*(.*?)\*', r'<b>\1</b>', clean_val)
                except Exception:
                    pass

            tg_args[key] = clean_val

    tg_args['audio_info'] = get_audio_info(args.rating_key, log_enabled)

    try:
        tg_body = TEMPLATES_TELEGRAM[args.media_type].format_map(tg_args)
        # Remove quebras de linha duplas no final se a sinopse estiver vazia
        tg_body = tg_body.strip()
        send_telegram_html(tg_body, args.poster, log_enabled)
    except Exception as e:
        log(f"Erro Template Telegram: {e}", log_enabled)
