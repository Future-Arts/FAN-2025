# region scraper settings 
URL = 'https://en.wikipedia.org/wiki/Volcanism_of_the_Mount_Edziza_volcanic_complex'
# endregion

# region image collection settings
MIN_IMG_DIMENSIONS = {
    'width' : 64,
    'height' : 64,
}

IMG_FILETYPES = [
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif', 
    '.webp', '.svg', '.heic', '.heif', '.ico', '.avif', '.jfif'
]
# endregion
# region text  collection settings
TEXT_FILETYPES = [
    '.txt', '.pdf', '.doc', '.docx', '.rtf', '.odt', '.md', 
    '.tex', '.wks', '.wps', '.wpd'
]
# endregion
# region audio collection settings
AUDIO_FILETYPES = [
    '.mp3', '.wav', '.aac', '.flac', '.ogg', '.m4a', '.wma', 
    '.alac', '.aiff', '.opus', '.amr', '.pcm'
]
# endregion
# region video collection settings
VIDEO_FILETYPES = [
    '.mp4', '.avi', '.mkv', '.mov', '.flv', '.wmv', '.webm', 
    '.mpeg', '.mpg', '.m4v', '.3gp', '.ogv', '.vob'
]
# endregion