#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
1. Instale o módulo requests para python.
      pip install requests

Tautulli > Settings > Notification Agents > Scripts > Bell icon:
      [X] Notify on Recently Added
Tautulli > Settings > Notification Agents > Scripts > Gear icon:
      Playback Recently Added: webhook_notify_url.py
Tautulli > Settings > Notifications > Script > Script Arguments:
      -sn {show_name} -ena {episode_name} -ssn {season_num00} -enu {episode_num00} -dur {duration}
      -med {media_type} -tt {title} -pos {poster_url} -genres {genres} -rating {rating} 
      -summary {summary} -year {year} -lname {library_name} -vr {video_resolution} -cr {content_rating}
      -servn {server_name} -ds {datestamp:DD/MM/YYYY} -st {studio} -di {directors} -ac {actors} 
      -dt {duration_time} -vw {video_width} -vh {video_height} -fs {file_size} -sy {show_year}
2. Argumentos Opcionais:
      -auth -log
"""

from __future__ import unicode_literals
import argparse
import requests
import time

# --- CONFIGURAÇÕES GERAIS ---
CONFIG = {
    "webhook_url": 'http://you_ip:3000/send/image',
    "phone": 'you_id@s.whatsapp.net', # Para Canal: @newsletter, Grupo: @g.us, Privado: @s.whatsapp.net
    "token": 'Basic SUA CREDENCIAL', # Opicional. Caso tenha colocado autenticao no go-whatsapp-web-multidevice
    "log_file_path": '/config/notify_whatsapp.log'
}

# --- TEMPLATES DE MENSAGEM ---
TEMPLATES = {
    "movie": "🍿 *Título:* {title} ({year})\n🕓 *Duração:* {duration} minutos\n🎭 *Gênero:* {genres} {actors} {rating} {summary}",
    "episode": "🍿 *Título:* {show_name} ({year})\n🔢 *Episódio:* {season_num}x{episode_num} - {episode_name}\n🕓 *Duração:* {duration} minutos\n🎭 *Gênero:* {genres} {actors} {rating} {summary}",
    "show": "🍿 *Título:* {show_name} ({show_year})\n🎭 *Gênero:* {genres} {actors} {rating} {summary}",
    "season": "🍿 *Título:* {show_name} ({show_year})\n🎬 *Temporada:* {season_num}\n🎭 *Gênero:* {genres} {actors} {rating} {summary}"
}

def log(message, log_enabled):
    """Grava uma mensagem de log no arquivo se o log estiver ativado."""
    if log_enabled:
        with open(CONFIG['log_file_path'], 'a', encoding='utf-8') as log_file:
            log_file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")

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
    """Envia os dados para o webhook, usando a URL da imagem com um parâmetro de extensão falso."""
    try:
        headers = {}
        if auth_enabled:
            headers['Authorization'] = CONFIG['token']

        multipart_data = {
            'phone': (None, CONFIG['phone']),
            'image_url': (None, poster_url),
            'caption': (None, body_text),
            'compress': (None, 'true')
        }

        response = requests.post(CONFIG['webhook_url'], files=multipart_data, headers=headers)
        log(f"Webhook response: {response.status_code} - {response.text}", log_enabled)
        return response.status_code
    except Exception as e:
        log(f"Error sending webhook: {e}", log_enabled)
        return None

if __name__ == '__main__':
    args = build_arguments()
    log_enabled = args.log_enabled

    log("Script started", log_enabled)
    log(f"Arguments: {args}", log_enabled)

    if not args.poster:
        log("Poster URL is missing. Cannot send notification.", log_enabled)
        exit()
        
    if args.media_type not in TEMPLATES:
        log(f"Unsupported media type: {args.media_type}", log_enabled)
        exit()

    from collections import defaultdict
    format_args = defaultdict(str, vars(args))
    body_text = TEMPLATES[args.media_type].format_map(format_args)

    poster_url_for_api = f"{args.poster}.png"
    log(f"Using modified URL for API: {poster_url_for_api}", log_enabled)

    send_webhook(body_text, poster_url_for_api, log_enabled, auth_enabled=args.auth)

    log("Script completed", log_enabled)
