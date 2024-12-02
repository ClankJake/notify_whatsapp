#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
1. Install the requests and Pillow modules for python.
       pip install requests
       pip install pillow

Tautulli > Settings > Notification Agents > Scripts > Bell icon:
        [X] Notify on Recently Added
Tautulli > Settings > Notification Agents > Scripts > Gear icon:
        Playback Recently Added: webhook_notify.py
Tautulli > Settings > Notifications > Script > Script Arguments:
        -sn {show_name} -ena {episode_name} -ssn {season_num00} -enu {episode_num00} -dur {duration}
        -srv {server_name} -med {media_type} -tt {title} -purl {plex_url} -pos {poster_url}
        -genres {genres} -rating {rating} -summary {summary} -year {year} -lname {library_name}
"""

from __future__ import unicode_literals
import argparse
import requests
import os
import time
from urllib.parse import urlparse

# ## EDIT THESE SETTINGS ##
WEBHOOK_URL = 'http://you_ip:3000/send/image'
PHONE = '"CODIGO DO CANAL"@newsletter'
LOG_FILE_PATH = '/config/notfify_whatsapp.log'

MOVIE_TEXT = "🎬  *Título:* {title} ({year})\n🕓  *Duração:* {duration} minutos\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n⭐ *{rating}* | {summary}"
TV_TEXT = "📺  *Série:* {show_name} ({year})\n🔢  *Episódio:* {season_num00}x{episode_num00} - {episode_name}\n🕓  *Duração:* {duration} minutos\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n*Sinopse:*\n⭐ *{rating}* | {summary}"
SHOW_TEXT = "📺  *Séries:* {show_name} ({year})\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n*Sinopse:*\n⭐ *{rating}* | {summary}"
SEASON_TEXT = "📺  *Série:* {show_name}\n📺  *Temporada:* {season_num00}\n🎭  *Gênero:* {genres}\n📺  *Biblioteca:* {library_name}\n\n*Sinopse:*\n⭐ *{rating}* | {summary}"

def log(message, log_enabled):
    if log_enabled:
        with open(LOG_FILE_PATH, 'a') as log_file:
            log_file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")

def download_image(url, filename, max_retries=3, retry_delay=10, log_enabled=False):
    for attempt in range(max_retries):
        try:
            request = requests.get(url, stream=True)
            if request.status_code == 200:
                with open(filename, 'wb') as image:
                    for chunk in request.iter_content(1024):
                        image.write(chunk)
                log(f"Successfully downloaded image: {url}", log_enabled)
                return True
            elif request.status_code == 429:
                log(f"Failed to download image: HTTP {request.status_code}. Retrying in {retry_delay} seconds...", log_enabled)
                time.sleep(retry_delay)
            else:
                log(f"Failed to download image: HTTP {request.status_code}", log_enabled)
                return False
        except Exception as e:
            log(f"Error downloading image: {e}", log_enabled)
            if attempt < max_retries - 1:
                log(f"Retrying in {retry_delay} seconds...", log_enabled)
                time.sleep(retry_delay)
            else:
                return False

if __name__ == '__main__':
    parser = argparse.ArgumentParser()

    parser.add_argument('-sn', '--show_name', action='store', default='',
                        help='The name of the TV show')
    parser.add_argument('-ena', '--episode_name', action='store', default='',
                        help='The name of the episode')
    parser.add_argument('-ssn', '--season_num', action='store', default='',
                        help='The season number of the TV show')
    parser.add_argument('-enu', '--episode_num', action='store', default='',
                        help='The episode number of the TV show')
    parser.add_argument('-dur', '--duration', action='store', default='',
                        help='The duration of the content')
    parser.add_argument('-srv', '--plex_server', action='store', default='',
                        help='The name of the Plex server')
    parser.add_argument('-med', '--media_type', action='store', default='',
                        help='The media type (e.g., movie, episode, season, show)')
    parser.add_argument('-tt', '--title', action='store', default='',
                        help='The title of the media')
    parser.add_argument('-purl', '--plex_url', action='store', default='',
                        help='URL to Plex video')
    parser.add_argument('-pos', '--poster', action='store', default='',
                        help='The poster URL')
    parser.add_argument('-genres', '--genres', action='store', default='',
                        help='Genres of the media')
    parser.add_argument('-rating', '--rating', action='store', default='',
                        help='Rating of the media')
    parser.add_argument('-summary', '--summary', action='store', default='',
                        help='Summary of the media')
    parser.add_argument('-year', '--year', action='store', default='',
                        help='Release year of the media')
    parser.add_argument('-lname', '--library_name', action='store', default='',
                        help='Library media')
    parser.add_argument('-log', '--log_enabled', action='store_true',
                        help='Enable logging')

    p = parser.parse_args()
    log_enabled = p.log_enabled

    log("Script started", log_enabled)
    log(f"Arguments parsed: {p}", log_enabled)

    if p.media_type == 'movie':
        BODY_TEXT = MOVIE_TEXT.format(
            media_type=p.media_type, title=p.title, duration=p.duration, genres=p.genres, rating=p.rating,
            summary=p.summary, year=p.year, library_name=p.library_name)
    elif p.media_type == 'episode':
        BODY_TEXT = TV_TEXT.format(
            media_type=p.media_type, show_name=p.show_name, title=p.title,
            season_num00=p.season_num, episode_num00=p.episode_num, episode_name=p.episode_name,
            duration=p.duration, genres=p.genres, rating=p.rating, summary=p.summary, year=p.year, library_name=p.library_name)
    elif p.media_type == 'show':
        BODY_TEXT = SHOW_TEXT.format(
            media_type=p.media_type, title=p.title,
            genres=p.genres, rating=p.rating, summary=p.summary, year=p.year, show_name=p.show_name, library_name=p.library_name)
    elif p.media_type == 'season':
        BODY_TEXT = SEASON_TEXT.format(
            media_type=p.media_type, show_name=p.show_name, title=p.title, season_num00=p.season_num,
            genres=p.genres, rating=p.rating, summary=p.summary, year=p.year, library_name=p.library_name)
    else:
        log("Unsupported media type, exiting.", log_enabled)
        exit()

    # Extract the filename from the URL
    parsed_url = urlparse(p.poster)
    original_filename = os.path.basename(parsed_url.path)
    if not original_filename:
        original_filename = 'temp_image'
    if '.' not in original_filename:
        original_filename += '.jpg'  # Default to .jpg if no extension found

    original_image_path = original_filename

    image_downloaded = download_image(p.poster, original_image_path, log_enabled=log_enabled)

    # Envia os dados para o webhook
    if image_downloaded:
        log("Image ready, preparing to send webhook", log_enabled)
        with open(original_image_path, 'rb') as image_file:
            files = {
                'image': (original_image_path, image_file, 'image/jpeg')
            }
            data = {
                'phone': PHONE,
                'caption': BODY_TEXT,
                'compress': 'true',
                'view_once': 'false'
            }
            response = requests.post(WEBHOOK_URL, data=data, files=files)
            log(f"Webhook response: {response.status_code} - {response.text}", log_enabled)

        # Verifica a resposta
        print(response.status_code)

    log("Cleaning up images", log_enabled)

    # Delete the images after sending the webhook
    try:
        if os.path.exists(original_image_path):
            os.remove(original_image_path)
            log(f"Deleted original image: {original_image_path}", log_enabled)
    except Exception as e:
        log(f"Error deleting images: {e}", log_enabled)

    log("Script completed", log_enabled)
