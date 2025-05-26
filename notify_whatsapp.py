#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
1. Install the requests module for python.
       pip install requests

Tautulli > Settings > Notification Agents > Scripts > Bell icon:
        [X] Notify on Recently Added
Tautulli > Settings > Notification Agents > Scripts > Gear icon:
        Playback Recently Added: webhook_notify.py
Tautulli > Settings > Notifications > Script > Script Arguments:
        -sn {show_name} -ena {episode_name} -ssn {season_num00} -enu {episode_num00} -dur {duration}
        -med {media_type} -tt {title} -pos {poster_url} -genres {genres} -rating {rating} 
        -summary {summary} -year {year} -lname {library_name} -vr {video_resolution} -cr {content_rating}
        -servn {server_name} -ds {datestamp:DD/MM/YYYY} -st {studio} -di {directors} -ac {actors} 
        -dt {duration_time} -vw {video_width} -vh {video_height} -fs {file_size} -sy {show_year}
2. Optional Argument:
        -auth -log
"""

from __future__ import unicode_literals
import argparse
import requests
import os
import time
from urllib.parse import urlparse

# Configurações gerais
CONFIG = {
    "webhook_url": 'http://you_ip:3000/send/image',
    "phone": 'you_id@s.whatsapp.net', # Para Canal: @newsletter, Grupo: @g.us, Privado: @s.whatsapp.net
    "token": 'Basic SUA CREDENCIAL', # Opicional. Caso tenha colocado autenticao no go-whatsapp-web-multidevice
    "log_file_path": '/config/notify_whatsapp.log',
    "retry_delay": 10,
    "max_retries": 3
}

# Template Padrão caso queira modificar so fazer sua alterações.
TEMPLATES = {
    "movie": "🎬  *Título:* {title} ({year})\n🕓  *Duração:* {duration} minutos\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n⭐ *{rating}* | {summary}",
    "episode": "📺  *Série:* {show_name} ({year})\n🔢  *Episódio:* {season_num}x{episode_num} - {episode_name}\n🕓  *Duração:* {duration} minutos\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n⭐ *{rating}* | {summary}",
    "show": "📺  *Séries:* {show_name} ({year})\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n⭐ *{rating}* | {summary}",
    "season": "📺  *Série:* {show_name}\n📺  *Temporada:* {season_num}\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n⭐ *{rating}* | {summary}"
}

def log(message, log_enabled):
    """Log message to file if logging is enabled."""
    if log_enabled:
        with open(CONFIG['log_file_path'], 'a') as log_file:
            log_file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")

def download_image(url, filename, log_enabled):
    """Download an image from a URL."""
    for attempt in range(CONFIG['max_retries']):
        try:
            response = requests.get(url, stream=True)
            if response.status_code == 200:
                with open(filename, 'wb') as image:
                    for chunk in response.iter_content(1024):
                        image.write(chunk)
                log(f"Successfully downloaded image: {url}", log_enabled)
                return True
            elif response.status_code == 429:
                log(f"Rate limited: Retrying in {CONFIG['retry_delay']} seconds...", log_enabled)
                time.sleep(CONFIG['retry_delay'])
            else:
                log(f"Failed to download image: HTTP {response.status_code}", log_enabled)
                return False
        except Exception as e:
            log(f"Error downloading image: {e}", log_enabled)
            if attempt < CONFIG['max_retries'] - 1:
                time.sleep(CONFIG['retry_delay'])
            else:
                return False

def build_arguments():
    """Build and parse command-line arguments."""
    parser = argparse.ArgumentParser()

    # Lista de argumentos
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

    # Adiciona os argumentos ao parser
    for short, long, help_text, default, action in arguments:
        if action:
            parser.add_argument(short, long, help=help_text, default=default, action=action)
        else:
            parser.add_argument(short, long, help=help_text, default=default)

    # Retorna os argumentos analisados
    return parser.parse_args()

def send_webhook(body_text, image_path, log_enabled, auth_enabled):
    """Send data to the webhook."""
    try:
        headers = {}
        if auth_enabled:
            headers['Authorization'] = CONFIG['token']
			
        with open(image_path, 'rb') as image_file:
            files = {'image': (image_path, image_file, 'image/jpeg')}
            data = {
                'phone': CONFIG['phone'],
                'caption': body_text,
                'compress': 'true',
                'view_once': 'false'
            }
            response = requests.post(CONFIG['webhook_url'], data=data, files=files, headers=headers)
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

    if args.media_type not in TEMPLATES:
        log("Unsupported media type", log_enabled)
        exit()

    # Prepare the body text
    body_text = TEMPLATES[args.media_type].format(
        title=args.title, show_name=args.show_name, episode_name=args.episode_name,
        season_num=args.season_num, episode_num=args.episode_num, duration=args.duration,
        genres=args.genres, rating=args.rating, summary=args.summary, year=args.year,
        library_name=args.library_name, video_resolution=args.video_resolution, 
        content_rating=args.content_rating, studio=args.studio, directors=args.directors,
        actors=args.actors, duration_time=args.duration_time, video_width=args.video_width,
        video_height=args.video_height, file_size=args.file_size, server_name=args.server_name,
        datestamp=args.datestamp, show_year=args.show_year
    )

    parsed_url = urlparse(args.poster)
    original_filename = os.path.basename(parsed_url.path)

    # Define um nome padrão caso o arquivo não tenha nome na URL
    if not original_filename:
        original_filename = 'temp_image.jpg'
    elif '.' not in original_filename:
        original_filename += '.jpg'  # Adiciona .jpg se não houver extensão

    original_image_path = original_filename

    # Faz o download da imagem
    image_downloaded = download_image(args.poster, original_image_path, log_enabled=args.log_enabled)

    # Send the webhook
    if image_downloaded:
        send_webhook(body_text, original_filename, log_enabled, auth_enabled=args.auth)
        os.remove(original_filename)
        log("Cleaned up downloaded image", log_enabled)

    log("Script completed", log_enabled)
